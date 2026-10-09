import XCTest
@testable import Sappho

/// The server clamps `GET /api/audiobooks?limit=` to 2000 (default 50), so a
/// library bigger than that must be paged with `offset`. These tests run the
/// API against a mock server that applies the same clamp.
final class LibraryPagingTests: XCTestCase {

    private var authRepo: AuthRepository!
    private var api: SapphoAPI!
    private let serverURL = URL(string: "https://sappho.test.com")!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        authRepo = AuthRepository()
        authRepo.clear()
        let user = try! JSONDecoder().decode(LoginUser.self, from: Data(#"{"id":1,"username":"u","is_admin":0}"#.utf8))
        authRepo.store(serverURL: serverURL, token: "token-1", refreshToken: "refresh-1", user: user)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        api = SapphoAPI(authRepository: authRepo, session: URLSession(configuration: config))
    }

    override func tearDown() {
        authRepo.clear()
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Mock server

    private func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func ok(_ request: URLRequest, _ body: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
    }

    private func books(_ ids: some Sequence<Int>) -> [[String: Any]] {
        ids.map { ["id": $0, "title": "Book \($0)"] }
    }

    /// A server holding `count` books that behaves like crud.js: limit
    /// defaults to 50 and is clamped to 2000; `total` is sent unless
    /// `sendsTotal` is false (older servers).
    private func serveLibrary(count: Int, sendsTotal: Bool = true) {
        MockURLProtocol.requestHandler = { [unowned self] request in
            let q = self.query(request)
            let limit = min(max(1, Int(q["limit"] ?? "") ?? 50), 2000)
            let offset = max(0, Int(q["offset"] ?? "") ?? 0)
            let ids = offset < count ? Array((offset + 1)...min(count, offset + limit)) : []
            var body: [String: Any] = ["audiobooks": self.books(ids)]
            if sendsTotal { body["total"] = count }
            return self.ok(request, self.json(body))
        }
    }

    private var listRequests: [URLRequest] {
        MockURLProtocol.capturedRequests.filter { $0.url!.path.hasSuffix("api/audiobooks") }
    }

    // MARK: - Whole library

    /// The reported bug: 2,364 books showed as 2,000.
    func testAllAudiobooksGetsPastTheServerClamp() async throws {
        serveLibrary(count: 2364)
        let all = try await api.getAllAudiobooks()
        XCTAssertEqual(all.count, 2364)
        XCTAssertEqual(Set(all.map(\.id)).count, 2364)
        XCTAssertEqual(all.first?.id, 1)
        XCTAssertEqual(all.last?.id, 2364)
    }

    func testPagesWithLimitAndOffsetAndStopsAtTotal() async throws {
        serveLibrary(count: 1500)
        _ = try await api.getAllAudiobooks()
        let pages = listRequests.map(query)
        XCTAssertEqual(pages.map { $0["offset"] }, ["0", "1000"])
        XCTAssertEqual(pages.map { $0["limit"] }, ["1000", "1000"])
    }

    func testSourceIsSentOnEveryPage() async throws {
        serveLibrary(count: 1200)
        _ = try await api.getAllAudiobooks(source: "4")
        let pages = listRequests.map(query)
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(pages.allSatisfy { $0["source"] == "4" })
    }

    func testSourceOmittedForAll() async throws {
        serveLibrary(count: 3)
        _ = try await api.getAllAudiobooks(source: SourceFilter.all.queryValue)
        XCTAssertTrue(listRequests.map(query).allSatisfy { $0["source"] == nil })
    }

    /// Two pages that overlap (a book added mid-fetch shifts the order).
    func testDuplicatesAcrossPagesAreDropped() async throws {
        MockURLProtocol.requestHandler = { [unowned self] request in
            let offset = Int(self.query(request)["offset"] ?? "0") ?? 0
            let ids: [Int]
            switch offset {
            case 0: ids = Array(1...1000)
            case 1000: ids = Array(1000...1100)   // 1000 repeated
            default: ids = []
            }
            return self.ok(request, self.json(["audiobooks": self.books(ids), "total": 1101]))
        }
        let all = try await api.getAllAudiobooks()
        XCTAssertEqual(all.count, 1100)
        XCTAssertEqual(Set(all.map(\.id)).count, 1100)
    }

    /// An empty page ends the fetch even if `total` promises more.
    func testEmptyPageStops() async throws {
        MockURLProtocol.requestHandler = { [unowned self] request in
            let offset = Int(self.query(request)["offset"] ?? "0") ?? 0
            let ids = offset == 0 ? Array(1...1000) : []
            return self.ok(request, self.json(["audiobooks": self.books(ids), "total": 5000]))
        }
        let all = try await api.getAllAudiobooks()
        XCTAssertEqual(all.count, 1000)
        XCTAssertEqual(listRequests.count, 2)
    }

    /// Older servers send no `total`: keep paging until a short page.
    func testOlderServerWithoutTotal() async throws {
        serveLibrary(count: 2364, sendsTotal: false)
        let all = try await api.getAllAudiobooks()
        XCTAssertEqual(all.count, 2364)
        XCTAssertEqual(listRequests.count, 3)
    }

    /// A server that ignores `offset` returns page one forever; that must end.
    func testServerIgnoringOffsetDoesNotLoopForever() async throws {
        MockURLProtocol.requestHandler = { [unowned self] request in
            self.ok(request, self.json(["audiobooks": self.books(1...1000), "total": 2364]))
        }
        let all = try await api.getAllAudiobooks()
        XCTAssertEqual(all.count, 1000)
        XCTAssertEqual(listRequests.count, 2)
    }

    // MARK: - Filtered lists (server default is 50 without a limit)

    func testGenreListIsNotCappedAtServerDefault() async throws {
        serveLibrary(count: 180)
        let books = try await api.getAudiobooksByGenre("Fantasy")
        XCTAssertEqual(books.count, 180)
        XCTAssertEqual(listRequests.first.map(query)?["genre"], "Fantasy")
    }

    func testAuthorAndSeriesListsAreNotCapped() async throws {
        serveLibrary(count: 75)
        let byAuthor = try await api.getAudiobooksByAuthor("Agatha Christie")
        let bySeries = try await api.getAudiobooksBySeries("Discworld")
        XCTAssertEqual(byAuthor.count, 75)
        XCTAssertEqual(bySeries.count, 75)
    }

    // MARK: - Library count

    func testBookCountUsesStatsEndpoint() async throws {
        MockURLProtocol.requestHandler = { [unowned self] request in
            XCTAssertTrue(request.url!.path.hasSuffix("api/audiobooks/meta/stats"))
            return self.ok(request, self.json(["totalBooks": 2364, "totalDuration": 123456]))
        }
        let count = try await api.getLibraryBookCount()
        XCTAssertEqual(count, 2364)
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    /// Servers without /meta/stats: one-book page, read its `total`.
    func testBookCountFallsBackToListTotal() async throws {
        MockURLProtocol.requestHandler = { [unowned self] request in
            if request.url!.path.hasSuffix("meta/stats") {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                        Data(#"{"error":"Not found"}"#.utf8))
            }
            XCTAssertEqual(self.query(request)["limit"], "1")
            return self.ok(request, self.json(["audiobooks": self.books([1]), "total": 2364]))
        }
        let count = try await api.getLibraryBookCount()
        XCTAssertEqual(count, 2364)
    }

    // MARK: - Decoding

    func testResponseDecodesTotal() throws {
        let json = Data(#"{"audiobooks": [{"id": 1, "title": "A"}], "total": 2364}"#.utf8)
        let response = try JSONDecoder().decode(AudiobooksResponse.self, from: json)
        XCTAssertEqual(response.audiobooks.count, 1)
        XCTAssertEqual(response.total, 2364)
    }

    func testResponseWithoutTotalDecodes() throws {
        let json = Data(#"{"audiobooks": [{"id": 1, "title": "A"}]}"#.utf8)
        let response = try JSONDecoder().decode(AudiobooksResponse.self, from: json)
        XCTAssertNil(response.total)
    }

    func testLibraryStatsDecodes() throws {
        let stats = try JSONDecoder().decode(LibraryStats.self, from: Data(#"{"totalBooks": 2364, "totalDuration": 98765.5}"#.utf8))
        XCTAssertEqual(stats.totalBooks, 2364)
        XCTAssertEqual(stats.totalDuration, 98765.5)
    }
}
