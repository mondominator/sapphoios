import XCTest
import AVFoundation
@testable import Sappho

// MARK: - A URLProtocol that answers slowly (or never)

/// Simulates a slow cellular link: each path can be given a delay, and
/// requests that match nothing hang until cancelled.
final class SlowURLProtocol: URLProtocol {
    struct Rule {
        let pathSuffix: String
        let delay: TimeInterval
        let status: Int
        let body: Data

        init(pathSuffix: String, delay: TimeInterval, status: Int, body: String) {
            self.init(pathSuffix: pathSuffix, delay: delay, status: status, data: Data(body.utf8))
        }

        init(pathSuffix: String, delay: TimeInterval, status: Int, data: Data) {
            self.pathSuffix = pathSuffix
            self.delay = delay
            self.status = status
            self.body = data
        }
    }

    private static let lock = NSLock()
    private static var _rules: [Rule] = []
    private static var _requests: [URLRequest] = []
    private static var _inFlight = 0
    private static var _maxInFlight = 0

    static var rules: [Rule] {
        get { lock.lock(); defer { lock.unlock() }; return _rules }
        set { lock.lock(); _rules = newValue; lock.unlock() }
    }
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }
    static var maxInFlight: Int {
        lock.lock(); defer { lock.unlock() }; return _maxInFlight
    }

    static func reset() {
        lock.lock()
        _rules = []
        _requests = []
        _inFlight = 0
        _maxInFlight = 0
        lock.unlock()
    }

    private var work: DispatchWorkItem?
    private var counted = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        Self._inFlight += 1
        Self._maxInFlight = max(Self._maxInFlight, Self._inFlight)
        counted = true
        let path = request.url?.path ?? ""
        let rule = Self._rules.first { path.hasSuffix($0.pathSuffix) }
        Self.lock.unlock()

        guard let rule else { return } // hang until stopLoading
        let url = request.url!
        let item = DispatchWorkItem { [weak self] in
            guard let self, let client = self.client else { return }
            self.uncount()
            let response = HTTPURLResponse(url: url, statusCode: rule.status, httpVersion: nil, headerFields: nil)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: rule.body)
            client.urlProtocolDidFinishLoading(self)
        }
        work = item
        DispatchQueue.global().asyncAfter(deadline: .now() + rule.delay, execute: item)
    }

    override func stopLoading() {
        work?.cancel()
        uncount()
    }

    private func uncount() {
        Self.lock.lock()
        if counted {
            counted = false
            Self._inFlight -= 1
        }
        Self.lock.unlock()
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

    func testEachSectionIsPublishedAsSoonAsItAnswers() async {
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        var firstLoadedAt: [HomeSectionKind: Date] = [:]
        store.addListener { kind in
            guard let kind, store.state(kind).status == .loaded, firstLoadedAt[kind] == nil else { return }
            firstLoadedAt[kind] = Date()
        }

        let start = Date()
        await store.refresh(timeout: 1.0) { kind in
            if kind == .upNext {
                try await Task.sleep(nanoseconds: 30_000_000_000) // a stalled request
            }
            return [book(kind == .continueListening ? 1 : 2)]
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 3, "the stalled section is cut off at its own deadline")
        XCTAssertEqual(store.state(.upNext).status, .failed(.timedOut))
        for kind in [HomeSectionKind.continueListening, .recentlyAdded, .listenAgain] {
            XCTAssertEqual(store.state(kind).status, .loaded, "\(kind) must not wait for Up Next")
            let at = try? XCTUnwrap(firstLoadedAt[kind])
            XCTAssertLessThan(at.map { $0.timeIntervalSince(start) } ?? 99, 0.5, "\(kind) published before the stalled section gave up")
        }
    }

    func testAFailedSectionKeepsItsSavedBooksAndOthersStillRefresh() async {
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        await store.refresh(timeout: 1) { _ in [book(1), book(2)] }

        await store.refresh(timeout: 1) { kind in
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
        await first.refresh(timeout: 1) { kind in kind == .continueListening ? [book(7, "Saved")] : [] }
        try await Task.sleep(nanoseconds: 300_000_000) // snapshot is written off the main thread

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
        await store.refresh(timeout: 1) { _ in throw URLError(.cannotConnectToHost) }
        XCTAssertTrue(store.allFailedForConnectivity)
        XCTAssertNil(store.serverErrorMessage)

        await store.refresh(timeout: 1) { _ in throw APIError.httpError(statusCode: 500, message: "boom") }
        XCTAssertFalse(store.allFailedForConnectivity)
        XCTAssertEqual(store.serverErrorMessage, "boom")
    }

    func testDeadlineDoesNotWaitForAnOperationThatIgnoresCancellation() async {
        let start = Date()
        do {
            _ = try await Deadline.run(seconds: 0.2) {
                // Ignores cancellation, like a socket stuck in a slow read.
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) { c.resume() }
                }
                return 1
            }
            XCTFail("should have timed out")
        } catch {
            XCTAssertTrue(error is DeadlineExceeded)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testDeadlinePassesThroughAFastResult() async throws {
        let value = try await Deadline.run(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testFailureClassification() {
        XCTAssertEqual(HomeSectionFailure.classify(DeadlineExceeded()), .timedOut)
        XCTAssertEqual(HomeSectionFailure.classify(APIError.networkError(URLError(.timedOut))), .timedOut)
        XCTAssertEqual(HomeSectionFailure.classify(APIError.networkError(URLError(.notConnectedToInternet))), .unreachable)
        XCTAssertEqual(HomeSectionFailure.classify(APIError.httpError(statusCode: 500, message: "x")), .server("x"))
    }

    /// End to end through the real API client over a slow link: the in-progress
    /// list answers at once, Up Next never does. Continue Listening must be on
    /// screen long before Up Next gives up.
    func testRealAPIOverSlowLinkPublishesFastSectionsFirst() async {
        SlowURLProtocol.reset()
        defer { SlowURLProtocol.reset() }
        SlowURLProtocol.rules = [
            .init(pathSuffix: "meta/in-progress", delay: 0.05, status: 200, body: booksJSON([1, 2])),
            .init(pathSuffix: "meta/recent", delay: 0.1, status: 200, body: booksJSON([3])),
            .init(pathSuffix: "meta/finished", delay: 0.1, status: 200, body: booksJSON([4]))
            // meta/up-next: hangs
        ]
        let repo = AuthRepository()
        repo.clear()
        repo.store(serverURL: URL(string: "https://sappho.test")!, token: "t", refreshToken: nil, user: makeLoginUser(id: 1))
        defer { repo.clear() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowURLProtocol.self]
        let api = SapphoAPI(authRepository: repo, session: URLSession(configuration: config))

        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        let start = Date()
        var continueListeningAt: TimeInterval?
        store.addListener { kind in
            if kind == .continueListening, store.state(.continueListening).status == .loaded {
                continueListeningAt = Date().timeIntervalSince(start)
            }
        }
        await store.refresh(timeout: 2, fetch: HomeFeedStore.apiFetcher(api))

        XCTAssertEqual(store.books(.continueListening).map(\.id), [1, 2])
        XCTAssertLessThan(continueListeningAt ?? 99, 1, "Continue Listening must not wait for Up Next")
        XCTAssertEqual(store.state(.upNext).status, .failed(.timedOut))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
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
        SlowURLProtocol.reset()
        defer { SlowURLProtocol.reset() }
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        SlowURLProtocol.rules = [.init(pathSuffix: "/cover", delay: 0.2, status: 200, data: png)]

        let repo = AuthRepository()
        repo.clear()
        let server = URL(string: "https://covers-\(UUID().uuidString).test")!
        repo.store(serverURL: server, token: "t", refreshToken: nil, user: makeLoginUser(id: 1))
        defer { repo.clear() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowURLProtocol.self]
        let api = SapphoAPI(authRepository: repo, session: URLSession(configuration: config))
        let loader = CoverThumbnailLoader(session: URLSession(configuration: config))
        loader.maxConcurrent = 3

        var done = 0
        for id in 1...10 {
            loader.load(audiobookId: id, width: CoverURL.listThumbnailWidth, api: api) { _ in done += 1 }
        }
        loader.load(audiobookId: 1, width: CoverURL.listThumbnailWidth, api: api) { _ in done += 1 }

        let deadline = Date().addingTimeInterval(5)
        while done < 11, Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }

        XCTAssertEqual(done, 11)
        let urls = SlowURLProtocol.requests.compactMap(\.url)
        XCTAssertEqual(urls.count, 10, "one request per cover, duplicates joined")
        XCTAssertTrue(urls.allSatisfy { $0.query == "width=120" }, "thumbnails, never originals: \(urls)")
        XCTAssertLessThanOrEqual(SlowURLProtocol.maxInFlight, 3, "a few at a time, not 100 at once")
    }
}

// MARK: - The same scenarios through CarPlayContentProvider
//
// These mirror scenarios that were run against the pre-fix
// CarPlayContentProvider.homeSections (which awaited all four lists in
// sequence) and failed there: Home blocked > 3 s behind a stalled Up Next,
// no saved feed after a relaunch on a dead link, and 20 full-size covers
// requested at once.

@MainActor
final class CarPlayProviderSlowLinkTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        SlowURLProtocol.reset()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CarPlayHome-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        SlowURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    private func makeAPI() -> (SapphoAPI, AuthRepository, URLSession) {
        let repo = AuthRepository()
        repo.clear()
        repo.store(serverURL: URL(string: "https://cp-\(UUID().uuidString).test")!, token: "t", refreshToken: nil, user: makeLoginUser(id: 1))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowURLProtocol.self]
        let session = URLSession(configuration: config)
        return (SapphoAPI(authRepository: repo, session: session), repo, session)
    }

    func testHomeShowsFastSectionsWhileOneStalls() async {
        SlowURLProtocol.rules = [
            .init(pathSuffix: "meta/in-progress", delay: 0.05, status: 200, body: booksJSON([1, 2])),
            .init(pathSuffix: "meta/recent", delay: 0.05, status: 200, body: booksJSON([3])),
            .init(pathSuffix: "meta/finished", delay: 0.05, status: 200, body: booksJSON([4])),
            .init(pathSuffix: "/cover", delay: 0.05, status: 404, body: "")
        ]
        let (api, repo, session) = makeAPI(); defer { repo.clear() }
        let provider = CarPlayContentProvider(api: api, coverLoader: CoverThumbnailLoader(session: session))
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")

        let shown = expectation(description: "Home has a book row")
        shown.assertForOverFulfill = false
        store.addListener { _ in
            let sections = provider.homeSections(store: store, onSelect: { _ in }, onRetry: {})
            if sections.contains(where: { $0.header == "In Progress" }) { shown.fulfill() }
        }
        let refresh = Task { await store.refresh(timeout: 10, fetch: HomeFeedStore.apiFetcher(api)) }
        await fulfillment(of: [shown], timeout: 3)
        refresh.cancel()
    }

    func testSavedFeedShownWhenServerUnreachable() async throws {
        SlowURLProtocol.rules = [
            .init(pathSuffix: "meta/in-progress", delay: 0, status: 200, body: booksJSON([1, 2])),
            .init(pathSuffix: "meta/up-next", delay: 0, status: 200, body: booksJSON([5])),
            .init(pathSuffix: "meta/recent", delay: 0, status: 200, body: booksJSON([3])),
            .init(pathSuffix: "meta/finished", delay: 0, status: 200, body: booksJSON([4])),
            .init(pathSuffix: "/cover", delay: 0, status: 404, body: "")
        ]
        let (api, repo, session) = makeAPI(); defer { repo.clear() }
        let first = HomeFeedStore(directory: directory)
        first.activate(account: "acct")
        await first.refresh(timeout: 5, fetch: HomeFeedStore.apiFetcher(api))
        try await Task.sleep(nanoseconds: 300_000_000)

        SlowURLProtocol.rules = ["meta/in-progress", "meta/up-next", "meta/recent", "meta/finished"].map {
            .init(pathSuffix: $0, delay: 0, status: 503, body: "{}")
        }
        let relaunched = HomeFeedStore(directory: directory)
        relaunched.activate(account: "acct")
        await relaunched.refresh(timeout: 5, fetch: HomeFeedStore.apiFetcher(api))
        let provider = CarPlayContentProvider(api: api, coverLoader: CoverThumbnailLoader(session: session))
        let sections = provider.homeSections(store: relaunched, onSelect: { _ in }, onRetry: {})
        XCTAssertTrue(sections.contains { $0.header == "Up Next" }, "saved feed: \(sections.map { $0.header ?? "-" })")
    }

    func testCoversAreThumbnailsAndThrottled() async throws {
        SlowURLProtocol.rules = [
            .init(pathSuffix: "meta/in-progress", delay: 0, status: 200, body: booksJSON(Array(1...20))),
            .init(pathSuffix: "meta/up-next", delay: 0, status: 200, body: "[]"),
            .init(pathSuffix: "meta/recent", delay: 0, status: 200, body: "[]"),
            .init(pathSuffix: "meta/finished", delay: 0, status: 200, body: "[]"),
            .init(pathSuffix: "/cover", delay: 0.3, status: 404, body: "")
        ]
        let (api, repo, session) = makeAPI(); defer { repo.clear() }
        let store = HomeFeedStore(directory: directory)
        store.activate(account: "acct")
        await store.refresh(timeout: 5, fetch: HomeFeedStore.apiFetcher(api))
        let provider = CarPlayContentProvider(api: api, coverLoader: CoverThumbnailLoader(session: session))
        _ = provider.homeSections(store: store, onSelect: { _ in }, onRetry: {})
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let covers = SlowURLProtocol.requests.compactMap(\.url).filter { $0.path.hasSuffix("/cover") }
        XCTAssertFalse(covers.isEmpty)
        XCTAssertTrue(covers.allSatisfy { $0.query == "width=120" }, "full-size covers requested: \(covers.prefix(2))")
        XCTAssertLessThanOrEqual(SlowURLProtocol.maxInFlight, 3, "concurrent requests: \(SlowURLProtocol.maxInFlight)")
    }
}

// MARK: - Starting playback

@MainActor
private final class FakePlayer: CarPlayPlaybackTarget {
    var events: [String] = []
    var played: Audiobook?
    func play(audiobook: Audiobook, startPosition: TimeInterval?) async {
        events.append("play")
        played = audiobook
    }
    func refreshAfterImmediateStart(audiobookId: Int, timeout: TimeInterval) async {
        events.append("refresh")
        try? await Task.sleep(nanoseconds: 60_000_000_000) // the server never answers
    }
}

@MainActor
final class CarPlayPlaybackStartTests: XCTestCase {
    func testTapShowsNowPlayingAndPlaysBeforeAnyServerRefresh() async throws {
        let player = FakePlayer()
        var shown = false
        let chapters = [Chapter(id: 1, audiobookId: 3, chapterNumber: 1, startTime: 0, duration: 60, title: "One")]
        let task = CarPlayPlaybackStarter.start(
            book(3), downloaded: book(3, chapters: chapters), player: player, showNowPlaying: { shown = true }
        )
        XCTAssertTrue(shown, "Now Playing is shown on the tap, not after the network")

        let deadline = Date().addingTimeInterval(1)
        while player.events.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(player.events.first, "play", "play must not wait on a metadata fetch")
        XCTAssertEqual(player.played?.chapters?.count, 1, "downloaded chapters used, no chapters request needed")
        task.cancel()
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

/// Wraps the real player to snapshot the requests made by the time play()
/// has returned (the server refresh legitimately follows it).
@MainActor
private final class RecordingTarget: CarPlayPlaybackTarget {
    let real: AudioPlayerService
    var requestsWhenPlaying: [URLRequest]?
    init(_ real: AudioPlayerService) { self.real = real }
    func play(audiobook: Audiobook, startPosition: TimeInterval?) async {
        await real.play(audiobook: audiobook, startPosition: startPosition)
        requestsWhenPlaying = SlowURLProtocol.requests
    }
    func refreshAfterImmediateStart(audiobookId: Int, timeout: TimeInterval) async {
        await real.refreshAfterImmediateStart(audiobookId: audiobookId, timeout: timeout)
    }
}

/// The acceptance test from the bug report: with the network hanging, a
/// downloaded book starts from its local file at the saved position, and no
/// request for that book is made before it is playing.
@MainActor
final class DownloadedBookPlaysWithoutNetworkTests: XCTestCase {
    private let bookId = 987_654
    private var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        SlowURLProtocol.reset()
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
        SlowURLProtocol.reset()
        try await super.tearDown()
    }

    func testDownloadedBookStartsAtOnceFromTheLocalFileWithNoRequests() async throws {
        let repo = AuthRepository()
        repo.clear()
        repo.store(serverURL: URL(string: "https://hang.test")!, token: "t", refreshToken: nil, user: makeLoginUser(id: 1))
        defer { repo.clear() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowURLProtocol.self] // no rules: every request hangs
        let api = SapphoAPI(authRepository: repo, session: URLSession(configuration: config))
        let player = AudioPlayerService()
        player.configure(api: api)

        let recorder = RecordingTarget(player)
        let start = Date()
        let task = CarPlayPlaybackStarter.start(book(bookId), downloaded: nil, player: recorder, showNowPlaying: {})
        let deadline = Date().addingTimeInterval(3)
        while !(player.isPlaying && player.currentAudiobook?.id == bookId && player.position >= 2), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(player.isPlaying)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "a downloaded book must not wait on the network")
        XCTAssertFalse(player.isBuffering, "local file: nothing to buffer")
        XCTAssertGreaterThanOrEqual(player.position, 2, "starts at the saved position")
        XCTAssertNotNil(recorder.requestsWhenPlaying, "play() returned")
        let bookRequests = (recorder.requestsWhenPlaying ?? []).filter {
            let path = $0.url?.path ?? ""
            return path.hasSuffix("/audiobooks/\(bookId)") || path.hasSuffix("/stream")
        }
        XCTAssertTrue(bookRequests.isEmpty, "no metadata or stream request before playing: \(bookRequests)")

        task.cancel()
        player.stop(syncProgress: false)
    }
}

private func makeLoginUser(id: Int) -> LoginUser {
    try! JSONDecoder().decode(LoginUser.self, from: Data(#"{"id":\#(id),"username":"u\#(id)","is_admin":0}"#.utf8))
}
