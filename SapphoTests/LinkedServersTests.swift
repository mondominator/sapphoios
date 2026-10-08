import XCTest
@testable import Sappho

/// Linked servers (server 0.16+): books mirrored from another Sappho server
/// carry `source` and `available`; new 5xx/4xx codes must never log out.
final class LinkedServersTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decodeBook(_ json: String) throws -> Audiobook {
        try decoder.decode(Audiobook.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testRemoteBookDecodesSourceAndAvailable() throws {
        let book = try decodeBook(#"""
        {"id": 901, "title": "Remote", "file_path": "sappho-remote://4/17",
         "source": {"id": 4, "name": "Robert"}, "available": true}
        """#)
        XCTAssertEqual(book.source, BookSource(id: 4, name: "Robert"))
        XCTAssertEqual(book.available, true)
        XCTAssertTrue(book.isRemote)
        XCTAssertTrue(book.isAvailable)
    }

    func testLocalBookHasNullSource() throws {
        let book = try decodeBook(#"{"id": 1, "title": "Local", "source": null, "available": true}"#)
        XCTAssertNil(book.source)
        XCTAssertFalse(book.isRemote)
        XCTAssertTrue(book.isAvailable)
    }

    func testUnavailableRemoteBook() throws {
        let book = try decodeBook(#"""
        {"id": 902, "title": "Offline", "source": {"id": 4, "name": "Robert"}, "available": false}
        """#)
        XCTAssertTrue(book.isRemote)
        XCTAssertFalse(book.isAvailable)
    }

    /// Servers before 0.16 send neither field: local and available.
    func testOlderServerWithoutFieldsDecodes() throws {
        let book = try decodeBook(#"{"id": 3, "title": "Old server"}"#)
        XCTAssertNil(book.source)
        XCTAssertNil(book.available)
        XCTAssertFalse(book.isRemote)
        XCTAssertTrue(book.isAvailable)
    }

    func testAvailableAsSQLiteInteger() throws {
        XCTAssertEqual(try decodeBook(#"{"id": 1, "title": "A", "available": 0}"#).available, false)
        XCTAssertEqual(try decodeBook(#"{"id": 1, "title": "A", "available": 1}"#).available, true)
    }

    /// A malformed source must not make a whole book list fail to decode.
    func testMalformedSourceIsIgnored() throws {
        let book = try decodeBook(#"{"id": 1, "title": "A", "source": "Robert", "available": "yes"}"#)
        XCTAssertNil(book.source)
        XCTAssertTrue(book.isAvailable)
    }

    func testBookListDecodesMixedSources() throws {
        let json = #"""
        {"audiobooks": [
          {"id": 1, "title": "Local", "source": null, "available": true},
          {"id": 2, "title": "Remote", "source": {"id": 4, "name": "Robert"}, "available": false},
          {"id": 3, "title": "Old"}
        ]}
        """#
        let books = try decoder.decode(AudiobooksResponse.self, from: Data(json.utf8)).audiobooks
        XCTAssertEqual(books.map(\.isRemote), [false, true, false])
        XCTAssertEqual(books.map(\.isAvailable), [true, false, true])
    }

    /// The home feed cache and CarPlay re-encode books; the fields survive.
    func testEncodeRoundTripKeepsSource() throws {
        let book = Audiobook(id: 5, title: "R", source: BookSource(id: 4, name: "Robert"), available: false)
        let decoded = try decoder.decode(Audiobook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded.source, BookSource(id: 4, name: "Robert"))
        XCTAssertEqual(decoded.available, false)
    }

    func testWithChaptersKeepsSource() {
        let book = Audiobook(id: 5, title: "R", source: BookSource(id: 4, name: "Robert"), available: true)
        let copy = book.withChapters([])
        XCTAssertEqual(copy.source, book.source)
        XCTAssertEqual(copy.available, true)
    }

    func testDownloadMetaKeepsSource() throws {
        let book = Audiobook(id: 5, title: "R", source: BookSource(id: 4, name: "Robert"))
        let meta = try decoder.decode(DownloadedBookMeta.self, from: JSONEncoder().encode(DownloadedBookMeta(from: book)))
        XCTAssertEqual(meta.toAudiobook().source, BookSource(id: 4, name: "Robert"))
    }

    /// Download metadata saved by 1.0.2 has no `source`.
    func testOldDownloadMetaDecodes() throws {
        let meta = try decoder.decode(DownloadedBookMeta.self, from: Data(#"{"id": 7, "title": "Old"}"#.utf8))
        XCTAssertNil(meta.source)
        XCTAssertFalse(meta.toAudiobook().isRemote)
    }

    func testLinkedSourcesDecode() throws {
        let sources = try decoder.decode([LinkedSource].self, from: Data(#"[{"id": 4, "name": "Robert", "available": true}]"#.utf8))
        XCTAssertEqual(sources, [LinkedSource(id: 4, name: "Robert", available: true)])
    }

    // MARK: - Source filter

    func testSourceFilterQueryValues() {
        XCTAssertNil(SourceFilter.all.queryValue)
        XCTAssertEqual(SourceFilter.local.queryValue, "local")
        XCTAssertEqual(SourceFilter.server(id: 4, name: "Robert").queryValue, "4")
    }

    func testSourceFilterHiddenWithoutLinkedServers() {
        XCTAssertEqual(SourceFilter.options(for: []), [])
    }

    func testSourceFilterOptions() {
        let options = SourceFilter.options(for: [
            LinkedSource(id: 4, name: "Robert", available: true),
            LinkedSource(id: 9, name: "Ana", available: false)
        ])
        XCTAssertEqual(options.map(\.label), ["All", "This server", "Robert", "Ana"])
    }

    // MARK: - Policy

    func testRemoteBooksAreNotEditable() {
        let remote = Audiobook(id: 1, title: "R", source: BookSource(id: 4, name: "Robert"))
        let local = Audiobook(id: 2, title: "L")
        XCTAssertFalse(LinkedServerPolicy.canEdit(remote, isAdmin: true))
        XCTAssertTrue(LinkedServerPolicy.canEdit(local, isAdmin: true))
        XCTAssertFalse(LinkedServerPolicy.canEdit(local, isAdmin: false))
    }

    func testPlayability() {
        let offline = Audiobook(id: 1, title: "R", source: BookSource(id: 4, name: "Robert"), available: false)
        XCTAssertFalse(LinkedServerPolicy.isPlayable(offline, isDownloaded: false))
        XCTAssertTrue(LinkedServerPolicy.isPlayable(offline, isDownloaded: true), "a download plays offline")
        XCTAssertTrue(LinkedServerPolicy.isPlayable(Audiobook(id: 2, title: "Old server"), isDownloaded: false))
    }

    func testFriendlyMessages() {
        let offline = Audiobook(id: 1, title: "R", source: BookSource(id: 4, name: "Robert"), available: false)
        XCTAssertEqual(LinkedServerPolicy.unavailableMessage(for: offline), "Robert's library is offline right now. Try again later.")
        XCTAssertTrue(LinkedServerPolicy.playbackFailureMessage(for: offline, isNetworkError: false).contains("Robert"))
        XCTAssertEqual(LinkedServerPolicy.playbackFailureMessage(for: Audiobook(id: 2, title: "L"), isNetworkError: false), "Playback failed. Try again.")
        XCTAssertNil(LinkedServerPolicy.message(forErrorCode: nil))
        XCTAssertNil(LinkedServerPolicy.message(forErrorCode: "FILE_VERSION_CHANGED"))
    }
}

// MARK: - API: source parameter, sources list, and the error-to-logout mapping

final class LinkedServersAPITests: XCTestCase {

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

    private func respond(_ status: Int, _ body: String) {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
    }

    private func queryItems(of request: URLRequest) -> [URLQueryItem] {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    func testGetAudiobooksSendsSource() async throws {
        respond(200, #"{"audiobooks": []}"#)
        _ = try await api.getAudiobooks(limit: 10, source: "4")
        let items = queryItems(of: MockURLProtocol.capturedRequests.last!)
        XCTAssertTrue(items.contains(URLQueryItem(name: "source", value: "4")))
    }

    func testGetAudiobooksOmitsSourceForAll() async throws {
        respond(200, #"{"audiobooks": []}"#)
        _ = try await api.getAudiobooks(limit: 10, source: SourceFilter.all.queryValue)
        let items = queryItems(of: MockURLProtocol.capturedRequests.last!)
        XCTAssertFalse(items.contains { $0.name == "source" })
    }

    func testGetLinkedSources() async throws {
        respond(200, #"[{"id": 4, "name": "Robert", "available": true}]"#)
        let sources = try await api.getLinkedSources()
        XCTAssertEqual(sources.map(\.name), ["Robert"])
        XCTAssertTrue(MockURLProtocol.capturedRequests.last!.url!.path.hasSuffix("api/linked-servers/sources"))
    }

    /// Servers before 0.16 have no such route: no linked servers.
    func testGetLinkedSourcesOnOlderServerIsEmpty() async throws {
        respond(404, #"{"error": "Not found"}"#)
        let sources = try await api.getLinkedSources()
        XCTAssertEqual(sources, [])
        XCTAssertEqual(authRepo.token, "token-1")
    }

    /// Every linked-server error keeps the session, never tries a refresh,
    /// and carries the server's code and a friendly message.
    func testLinkedServerErrorsNeverLogOut() async {
        let cases: [(Int, String)] = [
            (503, "REMOTE_UNAVAILABLE"),
            (502, "REMOTE_AUTH_FAILED"),
            (502, "REMOTE_ERROR"),
            (502, "REMOTE_INVALID"),
            (404, "REMOTE_BOOK_GONE"),
            (409, "REMOTE_BOOK_READ_ONLY")
        ]
        for (status, code) in cases {
            MockURLProtocol.reset()
            respond(status, #"{"error": "Linked server problem", "code": "\#(code)", "source": {"id": 4, "name": "Robert"}}"#)

            do {
                _ = try await api.getAudiobook(id: 901)
                XCTFail("\(code): should have thrown")
            } catch let APIError.httpError(statusCode, _, serverCode) {
                XCTAssertEqual(statusCode, status)
                XCTAssertEqual(serverCode, code)
            } catch {
                XCTFail("\(code): unexpected \(error)")
            }

            XCTAssertEqual(authRepo.token, "token-1", "\(code) must not clear the token")
            XCTAssertEqual(authRepo.refreshToken, "refresh-1", "\(code) must not clear the refresh token")
            XCTAssertTrue(authRepo.isAuthenticated, "\(code) must not log out")
            XCTAssertFalse(
                MockURLProtocol.capturedRequests.contains { $0.url!.path.hasSuffix("api/auth/refresh") },
                "\(code) must not trigger a token refresh"
            )
            XCTAssertNotNil(LinkedServerPolicy.message(forErrorCode: code), "\(code) has a friendly message")
            XCTAssertEqual(
                APIError.httpError(statusCode: status, message: "Linked server problem", code: code).errorDescription,
                LinkedServerPolicy.message(forErrorCode: code)
            )
        }
    }

    /// The same errors on a void request (progress sync on a remote book).
    func testLinkedServerErrorOnProgressKeepsSession() async {
        respond(503, #"{"error": "Remote unavailable", "code": "REMOTE_UNAVAILABLE"}"#)
        do {
            try await api.updateProgress(audiobookId: 901, position: 60)
            XCTFail("Should have thrown")
        } catch {}
        XCTAssertEqual(authRepo.token, "token-1")
    }

    /// Only a real 401 from our own server ends the session (after the
    /// refresh fails).
    func testOwn401StillLogsOut() async {
        respond(401, #"{"error": "Unauthorized"}"#)
        do {
            _ = try await api.getAudiobook(id: 1)
            XCTFail("Should have thrown")
        } catch {}
        XCTAssertNil(authRepo.token)
    }

    /// A numeric or unexpected `code` must not lose the message.
    func testUnexpectedCodeTypeKeepsMessage() async {
        respond(500, #"{"error": "Boom", "code": 42}"#)
        do {
            _ = try await api.getAudiobook(id: 1)
            XCTFail("Should have thrown")
        } catch let APIError.httpError(_, message, code) {
            XCTAssertEqual(message, "Boom")
            XCTAssertNil(code)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAuthFailurePolicyOnlyClearsOn401() {
        for status in [404, 409, 502, 503] {
            XCTAssertFalse(AuthFailurePolicy.shouldClearSession(statusCode: status, retriedWithFreshToken: false), "\(status)")
        }
        XCTAssertTrue(AuthFailurePolicy.shouldClearSession(statusCode: 401, retriedWithFreshToken: false))
    }
}
