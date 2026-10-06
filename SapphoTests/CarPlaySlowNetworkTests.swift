import XCTest
import AVFoundation
@testable import Sappho

// Every test here is deterministic on a slow, loaded machine: correctness is
// never decided by a sleep or a wall-clock bound. Tests wait on explicit
// signals (expectations fulfilled by the code under test, or by the fake
// server once a given set of requests has been answered); the expectation
// timeouts are only a guard against hanging forever.

/// Generous guard for expectations. Never part of what is being asserted.
private let hangGuard: TimeInterval = 60

// MARK: - A fake server that answers slowly, on demand, or never

/// Each test gets its own `FakeServer` with a unique host, so requests that a
/// previous test left in flight (hanging on purpose, or a background refresh
/// starting late) can never be counted against a later test.
final class SlowURLProtocol: URLProtocol {
    private static let registryLock = NSLock()
    private static var servers: [String: FakeServer] = [:]

    static func register(_ server: FakeServer) {
        registryLock.lock(); servers[server.host] = server; registryLock.unlock()
    }

    static func server(for host: String?) -> FakeServer? {
        guard let host else { return nil }
        registryLock.lock(); defer { registryLock.unlock() }
        return servers[host]
    }

    private var exchange: FakeServer.Exchange?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Unknown host: hang until cancelled.
        guard let server = Self.server(for: request.url?.host) else { return }
        exchange = server.start(request) { [weak self] status, body in
            guard let self, let client = self.client, let url = self.request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        exchange?.cancel()
    }
}

final class FakeServer: @unchecked Sendable {
    enum Reply {
        /// Answer after `delay` seconds (the delay only shapes overlap; no
        /// test depends on how long it really takes).
        case after(TimeInterval, status: Int, body: Data)
        /// Answer only when the test calls `release(_:)`.
        case held(status: Int, body: Data)
        /// Never answer.
        case hang
    }

    struct Rule {
        let pathSuffix: String
        let reply: Reply

        static func json(_ pathSuffix: String, _ body: String, delay: TimeInterval = 0, status: Int = 200) -> Rule {
            Rule(pathSuffix: pathSuffix, reply: .after(delay, status: status, body: Data(body.utf8)))
        }
        static func data(_ pathSuffix: String, _ body: Data, delay: TimeInterval = 0, status: Int = 200) -> Rule {
            Rule(pathSuffix: pathSuffix, reply: .after(delay, status: status, body: body))
        }
        static func held(_ pathSuffix: String, _ body: String, status: Int = 200) -> Rule {
            Rule(pathSuffix: pathSuffix, reply: .held(status: status, body: Data(body.utf8)))
        }
    }

    /// One request in flight. Answering and cancelling race; whichever comes
    /// first wins, and the in-flight count drops exactly once.
    final class Exchange {
        fileprivate let path: String
        fileprivate var deliver: ((Int, Data) -> Void)?
        fileprivate var work: DispatchWorkItem?
        fileprivate weak var server: FakeServer?
        init(path: String) { self.path = path }
        func cancel() { server?.finish(self, answered: false) }
    }

    let host = "\(UUID().uuidString.lowercased()).test"
    var baseURL: URL { URL(string: "https://\(host)")! }

    private let lock = NSLock()
    private var rules: [Rule]
    private var _requests: [URLRequest] = []
    private var _answered: [String] = []
    private var inFlight: [ObjectIdentifier: Exchange] = [:]
    private var _maxInFlight = 0
    private var held: [Exchange] = []
    private var waiters: [UUID: (check: (FakeServer) -> Bool, fire: () -> Void)] = [:]

    init(_ rules: [Rule] = []) {
        self.rules = rules
        SlowURLProtocol.register(self)
    }

    /// A session whose requests all go to this fake server.
    func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowURLProtocol.self]
        return URLSession(configuration: config)
    }

    func setRules(_ rules: [Rule]) {
        lock.lock(); self.rules = rules; lock.unlock()
    }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var maxInFlight: Int { lock.lock(); defer { lock.unlock() }; return _maxInFlight }

    func answeredCount(_ pathSuffix: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return _answered.filter { $0.hasSuffix(pathSuffix) }.count
    }

    func requestCount(_ pathSuffix: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return _requests.filter { ($0.url?.path ?? "").hasSuffix(pathSuffix) }.count
    }

    /// An expectation fulfilled (once) as soon as `condition` holds.
    func expectation(_ description: String, when condition: @escaping (FakeServer) -> Bool) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        lock.lock()
        waiters[UUID()] = (condition, { expectation.fulfill() })
        lock.unlock()
        evaluateWaiters()
        return expectation
    }

    /// Answer every held request whose path ends with `pathSuffix`.
    func release(_ pathSuffix: String) {
        lock.lock()
        let ready = held.filter { $0.path.hasSuffix(pathSuffix) }
        held.removeAll { $0.path.hasSuffix(pathSuffix) }
        lock.unlock()
        for exchange in ready {
            guard case .held(let status, let body)? = rule(for: exchange.path)?.reply else { continue }
            answer(exchange, status: status, body: body)
        }
    }

    fileprivate func start(_ request: URLRequest, deliver: @escaping (Int, Data) -> Void) -> Exchange {
        let path = request.url?.path ?? ""
        let exchange = Exchange(path: path)
        exchange.deliver = deliver
        exchange.server = self
        lock.lock()
        _requests.append(request)
        inFlight[ObjectIdentifier(exchange)] = exchange
        _maxInFlight = max(_maxInFlight, inFlight.count)
        let rule = rules.first { path.hasSuffix($0.pathSuffix) }
        if case .held? = rule?.reply { held.append(exchange) }
        lock.unlock()

        if case .after(let delay, let status, let body)? = rule?.reply {
            let work = DispatchWorkItem { [weak self] in self?.answer(exchange, status: status, body: body) }
            exchange.work = work
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
        }
        evaluateWaiters()
        return exchange
    }

    private func rule(for path: String) -> Rule? {
        lock.lock(); defer { lock.unlock() }
        return rules.first { path.hasSuffix($0.pathSuffix) }
    }

    private func answer(_ exchange: Exchange, status: Int, body: Data) {
        guard let deliver = claim(exchange) else { return }
        // Count it answered before the client sees it, so a waiter that
        // fires on "answered" never runs ahead of the bookkeeping.
        lock.lock(); _answered.append(exchange.path); lock.unlock()
        deliver(status, body)
        evaluateWaiters()
    }

    fileprivate func finish(_ exchange: Exchange, answered: Bool) {
        exchange.work?.cancel()
        _ = claim(exchange)
        evaluateWaiters()
    }

    /// Takes the exchange out of flight; nil if it already was.
    private func claim(_ exchange: Exchange) -> ((Int, Data) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        guard inFlight.removeValue(forKey: ObjectIdentifier(exchange)) != nil else { return nil }
        held.removeAll { $0 === exchange }
        let deliver = exchange.deliver
        exchange.deliver = nil
        return deliver
    }

    /// Fire (once each) every waiter whose condition now holds. Conditions
    /// read state under the lock themselves, so they run outside it.
    private func evaluateWaiters() {
        lock.lock()
        let current = waiters
        lock.unlock()
        let ready = current.filter { $0.value.check(self) }.map(\.key)
        guard !ready.isEmpty else { return }
        lock.lock()
        let toFire = ready.compactMap { waiters.removeValue(forKey: $0)?.fire }
        lock.unlock()
        toFire.forEach { $0() }
    }
}

/// A one-shot gate a test opens explicitly.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if open { lock.unlock(); continuation.resume(); return }
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func openGate() {
        lock.lock()
        open = true
        let waiting = continuations
        continuations = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }
}

private func book(_ id: Int, _ title: String = "Book", chapters: [Chapter]? = nil) -> Audiobook {
    let json = #"{"id":\#(id),"title":"\#(title)","duration":3600}"#
    let decoded = try! JSONDecoder().decode(Audiobook.self, from: Data(json.utf8))
    return chapters.map { decoded.withChapters($0) } ?? decoded
}

private func booksJSON(_ ids: [Int]) -> String {
    "[" + ids.map { #"{"id":\#($0),"title":"Book \#($0)","duration":3600}"# }.joined(separator: ",") + "]"
}

private func loaded(_ books: [Audiobook]) -> HomeSectionState {
    HomeSectionState(books: books, status: .loaded, updatedAt: Date())
}

private func makeLoginUser(id: Int) -> LoginUser {
    try! JSONDecoder().decode(LoginUser.self, from: Data(#"{"id":\#(id),"username":"u\#(id)","is_admin":0}"#.utf8))
}

/// A signed-in API client whose requests all go to `server`.
@MainActor
private func makeAPI(_ server: FakeServer) -> (SapphoAPI, AuthRepository) {
    let repo = AuthRepository()
    repo.clear()
    repo.store(serverURL: server.baseURL, token: "t", refreshToken: nil, user: makeLoginUser(id: 1))
    return (SapphoAPI(authRepository: repo, session: server.session()), repo)
}

// MARK: - Section loading: independent, bounded, cache-first

@MainActor
final class HomeFeedStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HomeFeedTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    /// Up Next is held until the other three sections are on screen. If the
    /// store waited for all sections, they would never appear (and Up Next
    /// would never be released): the expectation is the proof.
    func testEachSectionIsPublishedWithoutWaitingForTheOthers() async {
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        let upNextGate = Gate()
        let othersLoaded = expectation(description: "the three other sections are published")
        var upNextStatusWhenOthersLoaded: HomeSectionStatus?
        store.addListener { _ in
            let others: [HomeSectionKind] = [.continueListening, .recentlyAdded, .listenAgain]
            guard upNextStatusWhenOthersLoaded == nil,
                  others.allSatisfy({ store.state($0).status == .loaded }) else { return }
            upNextStatusWhenOthersLoaded = store.state(.upNext).status
            othersLoaded.fulfill()
        }

        let refresh = Task {
            await store.refresh(timeout: 600) { kind in
                if kind == .upNext { await upNextGate.wait() }
                return [book(kind == .continueListening ? 1 : 2)]
            }
        }
        await fulfillment(of: [othersLoaded], timeout: hangGuard)
        XCTAssertEqual(upNextStatusWhenOthersLoaded, .loading, "published while Up Next was still outstanding")

        upNextGate.openGate()
        await refresh.value
        XCTAssertEqual(store.state(.upNext).status, .loaded)
    }

    /// A section that never answers is cut off at its own deadline and marked
    /// timed out; the refresh finishes instead of hanging.
    func testAStalledSectionTimesOut() async {
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        let never = Gate()
        await store.refresh(timeout: 0.2) { kind in
            if kind == .upNext { await never.wait() }
            return []
        }
        XCTAssertEqual(store.state(.upNext).status, .failed(.timedOut))
        never.openGate()
    }

    func testAFailedSectionKeepsItsSavedBooksAndOthersStillRefresh() async {
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        await store.refresh(timeout: 600) { _ in [book(1), book(2)] }

        await store.refresh(timeout: 600) { kind in
            if kind == .upNext { throw APIError.networkError(URLError(.notConnectedToInternet)) }
            return [book(9)]
        }

        XCTAssertEqual(store.books(.upNext).map(\.id), [1, 2], "a failed refresh must not blank the section")
        XCTAssertEqual(store.state(.upNext).status, .failed(.unreachable))
        XCTAssertEqual(store.books(.recentlyAdded).map(\.id), [9])
        XCTAssertEqual(store.failedSections, [.upNext])
    }

    func testSavedFeedIsAvailableBeforeAnyNetwork() async throws {
        let first = HomeFeedStore(directory: directory)
        first.activate(account: "acct")
        await first.refresh(timeout: 600) { kind in kind == .continueListening ? [book(7, "Saved")] : [] }
        HomeFeedStore.waitForPendingWrites() // snapshot is written off the main thread

        // A cold start (e.g. CarPlay connecting in the car): nothing fetched yet.
        let relaunched = HomeFeedStore(directory: directory)
        relaunched.activate(account: "acct")
        XCTAssertEqual(relaunched.books(.continueListening).map(\.id), [7])
        XCTAssertEqual(relaunched.books(.continueListening).first?.title, "Saved")
        XCTAssertEqual(relaunched.state(.continueListening).status, .notLoaded)

        let otherAccount = HomeFeedStore(directory: directory)
        otherAccount.activate(account: "someone-else")
        XCTAssertFalse(otherAccount.hasAnyBooks, "the saved feed is per account")
    }

    func testOfflineAndServerErrorSummaries() async {
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        await store.refresh(timeout: 600) { _ in throw URLError(.cannotConnectToHost) }
        XCTAssertTrue(store.allFailedForConnectivity)
        XCTAssertNil(store.serverErrorMessage)

        await store.refresh(timeout: 600) { _ in throw APIError.httpError(statusCode: 500, message: "boom") }
        XCTAssertFalse(store.allFailedForConnectivity)
        XCTAssertEqual(store.serverErrorMessage, "boom")
    }

    /// The operation ignores cancellation and only finishes when the test
    /// opens its gate -- which happens after the deadline has been seen to
    /// fire. A Deadline that waited for the operation would never fire.
    func testDeadlineDoesNotWaitForAnOperationThatIgnoresCancellation() async {
        let gate = Gate()
        let timedOut = expectation(description: "deadline fired while the operation was still running")
        let run = Task {
            do {
                _ = try await Deadline.run(seconds: 0.1) {
                    await gate.wait() // no cancellation check, like a stuck socket read
                    return 1
                }
                XCTFail("should have timed out")
            } catch {
                XCTAssertTrue(error is DeadlineExceeded)
                timedOut.fulfill()
            }
        }
        await fulfillment(of: [timedOut], timeout: hangGuard)
        gate.openGate()
        await run.value
    }

    func testDeadlinePassesThroughAFastResult() async throws {
        let value = try await Deadline.run(seconds: 600) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testFailureClassification() {
        XCTAssertEqual(HomeSectionFailure.classify(DeadlineExceeded()), .timedOut)
        XCTAssertEqual(HomeSectionFailure.classify(APIError.networkError(URLError(.timedOut))), .timedOut)
        XCTAssertEqual(HomeSectionFailure.classify(APIError.networkError(URLError(.notConnectedToInternet))), .unreachable)
        XCTAssertEqual(HomeSectionFailure.classify(APIError.httpError(statusCode: 500, message: "x")), .server("x"))
    }

    /// End to end through the real API client: Up Next is held at the server
    /// until Continue Listening has been published.
    func testRealAPIPublishesContinueListeningWhileUpNextIsOutstanding() async {
        let server = FakeServer([
            .json("meta/in-progress", booksJSON([1, 2])),
            .json("meta/recent", booksJSON([3])),
            .json("meta/finished", booksJSON([4])),
            .held("meta/up-next", booksJSON([5]))
        ])
        let (api, repo) = makeAPI(server)
        defer { repo.clear() }

        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        let published = expectation(description: "Continue Listening published")
        var upNextAnsweredFirst = false
        store.addListener { kind in
            guard kind == .continueListening, store.state(.continueListening).status == .loaded else { return }
            upNextAnsweredFirst = server.answeredCount("meta/up-next") > 0
            published.fulfill()
        }
        let refresh = Task { await store.refresh(timeout: 600, fetch: HomeFeedStore.apiFetcher(api)) }
        await fulfillment(of: [published], timeout: hangGuard)

        XCTAssertFalse(upNextAnsweredFirst)
        XCTAssertEqual(store.books(.continueListening).map(\.id), [1, 2])
        XCTAssertEqual(store.state(.upNext).status, .loading)

        // Release Up Next only once its request has actually reached the server.
        await fulfillment(of: [server.expectation("up-next requested") { $0.requestCount("meta/up-next") > 0 }], timeout: hangGuard)
        server.release("meta/up-next")
        await refresh.value
        XCTAssertEqual(store.books(.upNext).map(\.id), [5])
    }
}

// MARK: - What CarPlay's Home shows

final class CarPlayHomeLayoutTests: XCTestCase {
    private func headers(_ sections: [CarPlayHomeSection]) -> [String?] { sections.map(\.header) }

    func testOfflineLeadsWithTheDownloadedCurrentBookThenDownloads() {
        let current = book(5, "Current")
        let downloaded = [book(5, "Current"), book(6, "Other download")]
        let sections = CarPlayHomeLayout.build(feed: [:], downloaded: downloaded, current: current, isConnected: false)

        XCTAssertEqual(headers(sections).prefix(2), ["Resume", "Downloaded"])
        XCTAssertEqual(sections[0].rows, [.book(current, isDownloaded: true)])
        XCTAssertEqual(sections[1].rows.compactMap(\.bookId), [6], "current book isn't listed twice")
        if case .status(let title, _, _) = sections.last?.rows.first {
            XCTAssertEqual(title, "Offline")
        } else {
            XCTFail("offline state is stated, not left blank")
        }
    }

    func testOfflineDoesNotOfferAStreamOnlyCurrentBookOnTop() {
        let sections = CarPlayHomeLayout.build(
            feed: [:], downloaded: [book(6)], current: book(5), isConnected: false
        )
        XCTAssertEqual(sections.first?.header, "Downloaded")
    }

    func testSlowLinkColdStartShowsSavedFeedAndDownloadsImmediately() {
        // Nothing has answered yet this session; the feed is the saved one.
        var feed: [HomeSectionKind: HomeSectionState] = [:]
        feed[.continueListening] = HomeSectionState(books: [book(1), book(2)], status: .loading, updatedAt: Date())
        feed[.upNext] = HomeSectionState(books: [book(3)], status: .loading, updatedAt: Date())
        let sections = CarPlayHomeLayout.build(feed: feed, downloaded: [book(8)], current: nil, isConnected: true)

        XCTAssertEqual(headers(sections), ["Resume", "Downloaded", "In Progress", "Up Next"])
        XCTAssertEqual(sections[0].rows.compactMap(\.bookId), [1])
    }

    func testFreshFeedOrderMatchesThePhoneWithDownloadsLast() {
        let feed: [HomeSectionKind: HomeSectionState] = [
            .continueListening: loaded([book(1), book(2)]),
            .upNext: loaded([book(3)]),
            .recentlyAdded: loaded([book(4)]),
            .listenAgain: loaded([book(5)])
        ]
        let sections = CarPlayHomeLayout.build(feed: feed, downloaded: [book(2), book(9)], current: nil, isConnected: true)
        XCTAssertEqual(headers(sections), ["Resume", "In Progress", "Up Next", "Recently Added", "Listen Again", "Downloaded"])
        XCTAssertEqual(sections[1].rows, [.book(book(2), isDownloaded: true)])
    }

    func testAFailedSectionKeepsSavedBooksAndOffersRetry() {
        var feed: [HomeSectionKind: HomeSectionState] = [
            .continueListening: loaded([book(1)]),
            .recentlyAdded: loaded([]),
            .listenAgain: loaded([])
        ]
        feed[.upNext] = HomeSectionState(books: [book(3)], status: .failed(.timedOut), updatedAt: Date())
        let sections = CarPlayHomeLayout.build(feed: feed, downloaded: [], current: nil, isConnected: true)

        XCTAssertTrue(headers(sections).contains("Up Next"), "saved books stay")
        XCTAssertEqual(sections.last?.rows, [.status(title: "Couldn't refresh", detail: "Showing saved books. Tap to retry.", retry: true)])
    }

    func testNeverBlank() {
        let loading = CarPlayHomeLayout.build(feed: [:], downloaded: [], current: nil, isConnected: true)
        XCTAssertEqual(loading.first?.rows.count, 1)

        var failed: [HomeSectionKind: HomeSectionState] = [:]
        for kind in HomeSectionKind.allCases {
            failed[kind] = HomeSectionState(books: [], status: .failed(.timedOut), updatedAt: nil)
        }
        let unreachable = CarPlayHomeLayout.build(feed: failed, downloaded: [], current: nil, isConnected: true)
        guard case .status(let title, _, let retry) = unreachable.first?.rows.first else {
            return XCTFail("expected a status row")
        }
        XCTAssertEqual(title, "Can't reach your Sappho server")
        XCTAssertTrue(retry)
    }

    func testCurrentBookFallsBackToLastPlayedFromDownloadsThenFeed() {
        let feed: [HomeSectionKind: HomeSectionState] = [.listenAgain: loaded([book(4, "From feed")])]
        XCTAssertEqual(CarPlayHomeLayout.currentBook(loaded: nil, lastPlayedId: 6, downloaded: [book(6, "Dl")], feed: feed)?.title, "Dl")
        XCTAssertEqual(CarPlayHomeLayout.currentBook(loaded: nil, lastPlayedId: 4, downloaded: [], feed: feed)?.title, "From feed")
        XCTAssertEqual(CarPlayHomeLayout.currentBook(loaded: book(1, "Loaded"), lastPlayedId: 4, downloaded: [], feed: feed)?.title, "Loaded")
        XCTAssertNil(CarPlayHomeLayout.currentBook(loaded: nil, lastPlayedId: nil, downloaded: [], feed: feed))
    }
}

// MARK: - Thumbnails

@MainActor
final class CoverThumbnailTests: XCTestCase {
    func testThumbnailURLAsksForAServerSupportedWidth() {
        let base = URL(string: "https://host.test/sappho")!
        XCTAssertEqual(CoverURL.make(baseURL: base, audiobookId: 12, width: 120).absoluteString,
                       "https://host.test/sappho/api/audiobooks/12/cover?width=120")
        XCTAssertEqual(CoverURL.make(baseURL: base, audiobookId: 12, width: 90).absoluteString,
                       "https://host.test/sappho/api/audiobooks/12/cover?width=120", "snapped up: the server ignores other widths")
        XCTAssertEqual(CoverURL.make(baseURL: base, audiobookId: 12, width: 2000).absoluteString,
                       "https://host.test/sappho/api/audiobooks/12/cover?width=600")
        XCTAssertEqual(CoverURL.make(baseURL: base, audiobookId: 12).absoluteString,
                       "https://host.test/sappho/api/audiobooks/12/cover")
    }

    func testLoaderFetchesSmallCoversAFewAtATimeAndDeduplicates() async throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        // The small delay makes covers overlap, so an unthrottled loader would
        // exceed the limit; the limit itself holds whatever the timing.
        let server = FakeServer([.data("/cover", png, delay: 0.05)])
        let (api, repo) = makeAPI(server)
        defer { repo.clear() }
        let loader = CoverThumbnailLoader(session: server.session())
        loader.maxConcurrent = 3

        let allDone = expectation(description: "every load completes")
        allDone.expectedFulfillmentCount = 11
        var images = 0
        for id in 1...10 {
            loader.load(audiobookId: id, width: CoverURL.listThumbnailWidth, api: api) { image in
                if image != nil { images += 1 }
                allDone.fulfill()
            }
        }
        // Same cover again while the first is in flight: joins it.
        loader.load(audiobookId: 1, width: CoverURL.listThumbnailWidth, api: api) { image in
            if image != nil { images += 1 }
            allDone.fulfill()
        }
        await fulfillment(of: [allDone], timeout: hangGuard)

        XCTAssertEqual(images, 11)
        let urls = server.requests.compactMap(\.url)
        XCTAssertEqual(urls.count, 10, "one request per cover, duplicates joined: \(urls.map(\.path))")
        XCTAssertTrue(urls.allSatisfy { $0.query == "width=120" }, "thumbnails, never originals: \(urls)")
        XCTAssertLessThanOrEqual(server.maxInFlight, 3, "a few at a time, not 100 at once")
    }
}

// MARK: - The same scenarios through CarPlayContentProvider
//
// These mirror scenarios that were run against the pre-fix
// CarPlayContentProvider.homeSections (which awaited all four lists in
// sequence) and failed there: Home stayed empty behind a stalled Up Next,
// no saved feed after a relaunch on a dead link, and 20 full-size covers
// requested at once.

@MainActor
final class CarPlayProviderSlowLinkTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CarPlayHome-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    /// Up Next never answers (and its deadline is far away), so CarPlay Home
    /// can only show In Progress if sections are independent.
    func testHomeShowsFastSectionsWhileOneStalls() async {
        let server = FakeServer([
            .json("meta/in-progress", booksJSON([1, 2])),
            .json("meta/recent", booksJSON([3])),
            .json("meta/finished", booksJSON([4])),
            .json("/cover", "", status: 404),
            FakeServer.Rule(pathSuffix: "meta/up-next", reply: .hang)
        ])
        let (api, repo) = makeAPI(server)
        defer { repo.clear() }
        let provider = CarPlayContentProvider(api: api, coverLoader: CoverThumbnailLoader(session: server.session()))
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")

        let shown = expectation(description: "Home has In Progress")
        shown.assertForOverFulfill = false
        store.addListener { _ in
            let sections = provider.homeSections(store: store, onSelect: { _ in }, onRetry: {})
            if sections.contains(where: { $0.header == "In Progress" }) { shown.fulfill() }
        }
        _ = Task { await store.refresh(timeout: 600, fetch: HomeFeedStore.apiFetcher(api)) }
        await fulfillment(of: [shown], timeout: hangGuard)
        XCTAssertEqual(store.state(.upNext).status, .loading)
        store.activate(account: nil) // cancels the outstanding refresh
    }

    func testSavedFeedShownWhenServerUnreachable() async throws {
        let server = FakeServer([
            .json("meta/in-progress", booksJSON([1, 2])),
            .json("meta/up-next", booksJSON([5])),
            .json("meta/recent", booksJSON([3])),
            .json("meta/finished", booksJSON([4])),
            .json("/cover", "", status: 404)
        ])
        let (api, repo) = makeAPI(server)
        defer { repo.clear() }
        let first = HomeFeedStore(directory: directory)
        first.activate(account: "acct")
        await first.refresh(timeout: 600, fetch: HomeFeedStore.apiFetcher(api))
        HomeFeedStore.waitForPendingWrites()

        server.setRules(["meta/in-progress", "meta/up-next", "meta/recent", "meta/finished"].map {
            .json($0, "{}", status: 503)
        } + [.json("/cover", "", status: 404)])
        let relaunched = HomeFeedStore(directory: directory)
        relaunched.activate(account: "acct")
        await relaunched.refresh(timeout: 600, fetch: HomeFeedStore.apiFetcher(api))
        let provider = CarPlayContentProvider(api: api, coverLoader: CoverThumbnailLoader(session: server.session()))
        let sections = provider.homeSections(store: relaunched, onSelect: { _ in }, onRetry: {})
        XCTAssertTrue(sections.contains { $0.header == "Up Next" }, "saved feed: \(sections.map { $0.header ?? "-" })")
    }

    func testCoversAreThumbnailsAndThrottled() async throws {
        let server = FakeServer([
            .json("meta/in-progress", booksJSON(Array(1...20))),
            .json("meta/up-next", "[]"),
            .json("meta/recent", "[]"),
            .json("meta/finished", "[]"),
            .json("/cover", "", delay: 0.05, status: 404)
        ])
        let (api, repo) = makeAPI(server)
        defer { repo.clear() }
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        await store.refresh(timeout: 600, fetch: HomeFeedStore.apiFetcher(api))

        // All 20 rows' covers answered: every cover request has been made.
        let coversDone = server.expectation("20 covers answered") { $0.answeredCount("/cover") >= 20 }
        let provider = CarPlayContentProvider(api: api, coverLoader: CoverThumbnailLoader(session: server.session()))
        let sections = provider.homeSections(store: store, onSelect: { _ in }, onRetry: {})
        XCTAssertEqual(sections.reduce(0) { $0 + $1.items.count }, 20)
        await fulfillment(of: [coversDone], timeout: hangGuard)

        let covers = server.requests.compactMap(\.url).filter { $0.path.hasSuffix("/cover") }
        XCTAssertEqual(covers.count, 20)
        XCTAssertTrue(covers.allSatisfy { $0.query == "width=120" }, "full-size covers requested: \(covers.prefix(2))")
        XCTAssertLessThanOrEqual(server.maxInFlight, 3, "concurrent requests: \(server.maxInFlight)")
    }
}

// MARK: - Starting playback

@MainActor
private final class FakePlayer: CarPlayPlaybackTarget {
    var events: [String] = []
    var played: Audiobook?
    let playCalled: XCTestExpectation
    let neverAnswers = Gate()

    init(playCalled: XCTestExpectation) { self.playCalled = playCalled }

    func play(audiobook: Audiobook, startPosition: TimeInterval?) async {
        events.append("play")
        played = audiobook
        playCalled.fulfill()
    }
    func refreshAfterImmediateStart(audiobookId: Int, timeout: TimeInterval) async {
        events.append("refresh")
        await neverAnswers.wait() // the server never answers
    }
}

@MainActor
final class CarPlayPlaybackStartTests: XCTestCase {
    func testTapShowsNowPlayingAndPlaysBeforeAnyServerRefresh() async throws {
        let player = FakePlayer(playCalled: expectation(description: "play called"))
        var shown = false
        let chapters = [Chapter(id: 1, audiobookId: 3, chapterNumber: 1, startTime: 0, duration: 60, title: "One")]
        let task = CarPlayPlaybackStarter.start(
            book(3), downloaded: book(3, chapters: chapters), player: player, showNowPlaying: { shown = true }
        )
        XCTAssertTrue(shown, "Now Playing is shown on the tap, not after the network")

        await fulfillment(of: [player.playCalled], timeout: hangGuard)
        XCTAssertEqual(player.events.first, "play", "play must not wait on a metadata fetch")
        XCTAssertEqual(player.played?.chapters?.count, 1, "downloaded chapters used, no chapters request needed")
        player.neverAnswers.openGate()
        await task.value
        XCTAssertEqual(player.events, ["play", "refresh"])
    }

    func testPolicies() {
        XCTAssertTrue(StreamStartPolicy.startImmediately(isLocalFile: false))
        XCTAssertFalse(StreamStartPolicy.startImmediately(isLocalFile: true))

        XCTAssertEqual(LateProgressPolicy.seekTarget(startedAt: 100, currentPosition: 110, resolvedServerPosition: 900), 900)
        XCTAssertNil(LateProgressPolicy.seekTarget(startedAt: 100, currentPosition: 110, resolvedServerPosition: 103), "no jump for a few seconds")
        XCTAssertNil(LateProgressPolicy.seekTarget(startedAt: 100, currentPosition: 200, resolvedServerPosition: 900), "never yank an active listener")

        let plain = book(3)
        XCTAssertNil(CarPlayPlaybackPlan.bookToPlay(tapped: plain, downloaded: nil).chapters)
        XCTAssertNil(CarPlayPlaybackPlan.bookToPlay(tapped: plain, downloaded: book(4, chapters: [])).chapters)
    }
}

/// Wraps the real player to snapshot the server's requests at the moment
/// play() returns (the server refresh legitimately follows it).
@MainActor
private final class RecordingTarget: CarPlayPlaybackTarget {
    let real: AudioPlayerService
    let server: FakeServer
    let played: XCTestExpectation
    var requestsWhenPlaying: [URLRequest]?
    var isPlayingWhenPlayReturned = false
    var positionWhenPlayReturned: TimeInterval = 0

    init(_ real: AudioPlayerService, server: FakeServer, played: XCTestExpectation) {
        self.real = real
        self.server = server
        self.played = played
    }

    func play(audiobook: Audiobook, startPosition: TimeInterval?) async {
        await real.play(audiobook: audiobook, startPosition: startPosition)
        requestsWhenPlaying = server.requests
        isPlayingWhenPlayReturned = real.isPlaying && real.currentAudiobook?.id == audiobook.id
        positionWhenPlayReturned = real.position
        played.fulfill()
    }

    func refreshAfterImmediateStart(audiobookId: Int, timeout: TimeInterval) async {
        await real.refreshAfterImmediateStart(audiobookId: audiobookId, timeout: timeout)
    }
}

/// The acceptance test from the bug report: with every request hanging, a
/// downloaded book starts from its local file at the saved position, and no
/// request for that book is made before it is playing. If play() waited on
/// the network it would never return and the expectation would not be met.
@MainActor
final class DownloadedBookPlaysWithoutNetworkTests: XCTestCase {
    private let bookId = 987_654
    private var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.set(bookId, forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.set(2, forKey: "lastPlayedPosition")

        // A real 5 s audio file where DownloadManager looks for downloads.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let downloads = appSupport.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1]
        do {
            let file = try AVAudioFile(forWriting: temp, settings: settings)
            let format = file.processingFormat
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 5))!
            buffer.frameLength = buffer.frameCapacity
            try file.write(from: buffer)
        }
        fileURL = downloads.appendingPathComponent("\(bookId).m4b")
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: temp, to: fileURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.removeObject(forKey: "lastPlayedPosition")
        try await super.tearDown()
    }

    func testDownloadedBookStartsFromTheLocalFileWithNoRequests() async throws {
        let server = FakeServer() // no rules: every request hangs
        let (api, repo) = makeAPI(server)
        defer { repo.clear() }
        let player = AudioPlayerService()
        player.configure(api: api)

        let recorder = RecordingTarget(player, server: server, played: expectation(description: "play() returned"))
        let task = CarPlayPlaybackStarter.start(book(bookId), downloaded: nil, player: recorder, showNowPlaying: {})
        await fulfillment(of: [recorder.played], timeout: hangGuard)

        XCTAssertTrue(recorder.isPlayingWhenPlayReturned)
        XCTAssertGreaterThanOrEqual(recorder.positionWhenPlayReturned, 2, "starts at the saved position")
        let bookRequests = (recorder.requestsWhenPlaying ?? []).filter {
            let path = $0.url?.path ?? ""
            return path.hasSuffix("/audiobooks/\(bookId)") || path.hasSuffix("/stream")
        }
        XCTAssertTrue(bookRequests.isEmpty, "no metadata or stream request before playing: \(bookRequests)")

        task.cancel()
        player.stop(syncProgress: false)
    }
}
