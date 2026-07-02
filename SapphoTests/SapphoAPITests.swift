import XCTest
@testable import Sappho

// MARK: - Mock URLProtocol for intercepting network requests

final class MockURLProtocol: URLProtocol {
    /// Handler to provide mock responses
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Captured requests for inspection
    static var capturedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: -1, userInfo: [NSLocalizedDescriptionKey: "No handler set"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }
}

// MARK: - SapphoAPI Tests

final class SapphoAPITests: XCTestCase {

    private var authRepo: AuthRepository!
    private var api: SapphoAPI!
    private var session: URLSession!

    private let testServerURL = URL(string: "https://sappho.test.com")!
    private let testToken = "test-token-abc123"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        authRepo = AuthRepository()
        authRepo.clear()

        // Store credentials so API considers us authenticated.
        // No refresh token by default — refresh-specific tests set one explicitly.
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        authRepo.store(serverURL: testServerURL, token: testToken, refreshToken: nil, user: loginUser)

        // Create URLSession with mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        api = SapphoAPI(authRepository: authRepo, session: session)
    }

    override func tearDown() {
        authRepo.clear()
        MockURLProtocol.reset()
        authRepo = nil
        api = nil
        session = nil
        super.tearDown()
    }

    // MARK: - URL Builders

    func testCoverURLConstruction() {
        let url = api.coverURL(for: 42)
        XCTAssertEqual(url?.absoluteString, "https://sappho.test.com/api/audiobooks/42/cover")
    }

    func testStreamURLConstruction() {
        let url = api.streamURL(for: 99)
        XCTAssertEqual(url?.absoluteString, "https://sappho.test.com/api/audiobooks/99/stream")
    }

    func testAvatarURLConstruction() {
        let url = api.avatarURL()
        XCTAssertEqual(url?.absoluteString, "https://sappho.test.com/api/profile/avatar")
    }

    func testCoverURLReturnsNilWithoutServerURL() {
        authRepo.clear()
        let freshAPI = SapphoAPI(authRepository: authRepo, session: session)
        XCTAssertNil(freshAPI.coverURL(for: 1))
    }

    func testStreamURLReturnsNilWithoutServerURL() {
        authRepo.clear()
        let freshAPI = SapphoAPI(authRepository: authRepo, session: session)
        XCTAssertNil(freshAPI.streamURL(for: 1))
    }

    func testAvatarURLReturnsNilWithoutServerURL() {
        authRepo.clear()
        let freshAPI = SapphoAPI(authRepository: authRepo, session: session)
        XCTAssertNil(freshAPI.avatarURL())
    }

    // MARK: - Auth Headers

    func testAuthHeadersWithToken() {
        let headers = api.authHeaders
        XCTAssertEqual(headers["Authorization"], "Bearer test-token-abc123")
    }

    func testAuthHeadersWithoutToken() {
        authRepo.clear()
        let freshAPI = SapphoAPI(authRepository: authRepo, session: session)
        XCTAssertTrue(freshAPI.authHeaders.isEmpty)
    }

    // MARK: - Login

    func testLoginSuccess() async throws {
        let responseJSON = """
        {
            "token": "new-token-xyz",
            "user": {
                "id": 5,
                "username": "mondo",
                "is_admin": 1
            }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/auth/login") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            // Verify request body
            if let body = request.httpBody {
                let decoded = try JSONDecoder().decode(LoginRequestPayload.self, from: body)
                XCTAssertEqual(decoded.username, "testuser")
                XCTAssertEqual(decoded.password, "testpass")
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseJSON)
        }

        let loginURL = URL(string: "https://sappho.test.com")!
        let result = try await api.login(serverURL: loginURL, username: "testuser", password: "testpass")

        XCTAssertEqual(result.token, "new-token-xyz")
        XCTAssertEqual(result.user.id, 5)
        XCTAssertEqual(result.user.username, "mondo")
        XCTAssertTrue(result.user.isAdminUser)
    }

    func testLoginFailsWithHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let errorJSON = """
            {"message": "Invalid credentials"}
            """.data(using: .utf8)!
            return (response, errorJSON)
        }

        let loginURL = URL(string: "https://sappho.test.com")!
        do {
            _ = try await api.login(serverURL: loginURL, username: "bad", password: "wrong")
            XCTFail("Should have thrown")
        } catch let error as APIError {
            if case .httpError(let code, let message) = error {
                XCTAssertEqual(code, 401)
                XCTAssertEqual(message, "Invalid credentials")
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - API Requests with Auth

    func testGetRecentlyAddedSendsAuthHeader() async throws {
        let responseJSON = """
        [
            {"id": 1, "title": "Book One"},
            {"id": 2, "title": "Book Two"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc123")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/meta/recent") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("limit=10") ?? false)

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getRecentlyAdded()
        XCTAssertEqual(books.count, 2)
        XCTAssertEqual(books[0].title, "Book One")
    }

    func testGetAudiobooksWithSearchQuery() async throws {
        let responseJSON = """
        {"audiobooks": [{"id": 42, "title": "Dune"}]}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("search=Dune") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let books = try await api.getAudiobooks(search: "Dune")
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Dune")
    }

    // MARK: - Error Handling: Not Authenticated

    func testRequestThrowsNotAuthenticatedWithoutCredentials() async {
        authRepo.clear()
        let unauthAPI = SapphoAPI(authRepository: authRepo, session: session)

        do {
            _ = try await unauthAPI.getRecentlyAdded()
            XCTFail("Should have thrown notAuthenticated")
        } catch let error as APIError {
            if case .notAuthenticated = error {
                // Expected
            } else {
                XCTFail("Expected notAuthenticated, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Error Handling: 401 Clears Auth

    func testHTTP401ClearsAuthRepository() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        XCTAssertTrue(authRepo.isAuthenticated)

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown")
        } catch {
            // After 401, auth should be cleared
            try? await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertFalse(authRepo.isAuthenticated)
        }
    }

    func testHTTP403ClearsAuthRepository() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        XCTAssertTrue(authRepo.isAuthenticated)

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown")
        } catch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertFalse(authRepo.isAuthenticated)
        }
    }

    // MARK: - Token Refresh on 401

    /// Re-store credentials including a refresh token.
    private func storeWithRefreshToken(_ refresh: String) {
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        authRepo.store(serverURL: testServerURL, token: testToken, refreshToken: refresh, user: loginUser)
    }

    func testLoginDecodesRefreshToken() async throws {
        let responseJSON = """
        {
            "token": "new-token-xyz",
            "refreshToken": "refresh-xyz",
            "user": { "id": 5, "username": "mondo", "is_admin": 1 }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await api.login(serverURL: testServerURL, username: "u", password: "p")
        XCTAssertEqual(result.token, "new-token-xyz")
        XCTAssertEqual(result.refreshToken, "refresh-xyz")
    }

    func test401WithRefreshTokenRefreshesAndRetries() async throws {
        storeWithRefreshToken("refresh-original")

        let booksJSON = """
        [{"id": 1, "title": "Book One"}]
        """.data(using: .utf8)!
        let refreshJSON = """
        {"token": "fresh-access", "refreshToken": "refresh-rotated"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("api/auth/refresh") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, refreshJSON)
            }
            // Protected endpoint: 401 with the stale token, 200 once the fresh one arrives.
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, booksJSON)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let books = try await api.getRecentlyAdded()
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "Book One")
        // Tokens rotated and persisted.
        XCTAssertEqual(authRepo.token, "fresh-access")
        XCTAssertEqual(authRepo.refreshToken, "refresh-rotated")
        XCTAssertTrue(authRepo.isAuthenticated)
    }

    func test401RefreshFailureClearsAuth() async {
        storeWithRefreshToken("refresh-stale")

        // Everything 401 — including the refresh call (refresh token is dead).
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown")
        } catch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertFalse(authRepo.isAuthenticated)
            XCTAssertNil(authRepo.token)
            XCTAssertNil(authRepo.refreshToken)
        }
    }

    func testRefreshRetriesOnlyOnce() async {
        storeWithRefreshToken("refresh-original")

        let refreshJSON = """
        {"token": "fresh-access", "refreshToken": "refresh-rotated"}
        """.data(using: .utf8)!

        // Protected endpoint ALWAYS 401 (even with the fresh token); refresh always
        // succeeds. The client must refresh once, retry once, then give up — not loop.
        MockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("api/auth/refresh") {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, refreshJSON)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown")
        } catch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertFalse(authRepo.isAuthenticated)
        }

        // Exactly one refresh, and exactly two protected calls (original + single retry).
        let refreshCalls = MockURLProtocol.capturedRequests.filter { ($0.url?.absoluteString ?? "").contains("api/auth/refresh") }
        XCTAssertEqual(refreshCalls.count, 1)
        let protectedCalls = MockURLProtocol.capturedRequests.filter { ($0.url?.absoluteString ?? "").contains("meta/recent") }
        XCTAssertEqual(protectedCalls.count, 2)
    }

    // MARK: - Error Handling: Server Error

    func testHTTP500ThrowsHTTPError() async {
        let errorJSON = """
        {"message": "Internal server error"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, errorJSON)
        }

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown")
        } catch let error as APIError {
            if case .httpError(let code, let message) = error {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(message, "Internal server error")
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Error Handling: Decoding Error

    func testDecodingErrorOnMalformedJSON() async {
        let badJSON = "not valid json at all".data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, badJSON)
        }

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown decodingError")
        } catch let error as APIError {
            if case .decodingError = error {
                // Expected
            } else {
                XCTFail("Expected decodingError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Progress Update

    func testUpdateProgressSendsCorrectBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/progress") ?? false)

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["position"] as? Int, 1500)
                XCTAssertEqual(json?["completed"] as? Int, 0)
                XCTAssertEqual(json?["state"] as? String, "playing")
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.updateProgress(audiobookId: 42, position: 1500, state: "playing")
    }

    // MARK: - Mark Finished

    func testMarkFinishedSendsCorrectBody() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")

            if let body = request.httpBody {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                XCTAssertEqual(json?["position"] as? Int, 0)
                XCTAssertEqual(json?["completed"] as? Int, 1)
                XCTAssertEqual(json?["state"] as? String, "stopped")
            }

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.markFinished(audiobookId: 42)
    }

    // MARK: - Get Health

    func testGetHealthDecodes() async throws {
        let responseJSON = """
        {"status": "ok", "message": "Server running", "version": "2.0.0"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let health = try await api.getHealth()
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.version, "2.0.0")
    }

    // MARK: - Toggle Favorite

    func testToggleFavorite() async throws {
        let responseJSON = """
        {"success": true, "is_favorite": true}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/10/favorite/toggle") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await api.toggleFavorite(audiobookId: 10)
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.isFavorite)
    }

    // MARK: - Get Chapters

    func testGetChapters() async throws {
        let responseJSON = """
        [
            {"id": 1, "audiobook_id": 42, "chapter_number": 1, "start_time": 0, "duration": 600, "title": "Prologue"},
            {"id": 2, "audiobook_id": 42, "chapter_number": 2, "start_time": 600, "duration": 900, "title": "Chapter 1"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("api/audiobooks/42/chapters") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let chapters = try await api.getChapters(audiobookId: 42)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "Prologue")
        XCTAssertEqual(chapters[1].startTime, 600)
    }

    // MARK: - Network Error

    func testNetworkErrorWrapsUnderlyingError() async {
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown networkError")
        } catch let error as APIError {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Server URL With Subpath (C2 regression)
    // A server behind a reverse proxy can live at a subpath, e.g.
    // https://host/sappho. URL(string:relativeTo:) resolves relative to the
    // host root and silently drops that subpath (RFC 3986); these tests pin
    // requestVoid and the multipart uploads to appendingPathComponent behavior.

    /// Re-store credentials with a server URL that includes a subpath.
    private func storeWithSubpathServerURL() {
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        let subpathURL = URL(string: "https://sappho.test.com/sappho")!
        authRepo.store(serverURL: subpathURL, token: testToken, refreshToken: nil, user: loginUser)
    }

    func testRequestVoidPreservesServerSubpath() async throws {
        storeWithSubpathServerURL()

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/sappho/api/audiobooks/42/progress")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.updateProgress(audiobookId: 42, position: 1500, state: "playing")

        let paths = MockURLProtocol.capturedRequests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/sappho/api/audiobooks/42/progress"])
    }

    func testUploadAvatarPreservesServerSubpath() async throws {
        storeWithSubpathServerURL()

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/sappho/api/profile/avatar")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await api.uploadAvatar(imageData: Data([0xFF, 0xD8]))

        let paths = MockURLProtocol.capturedRequests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/sappho/api/profile/avatar"])
    }

    func testUploadAudiobookPreservesServerSubpath() async throws {
        storeWithSubpathServerURL()

        let responseJSON = """
        {"message": "ok", "audiobook": {"id": 7, "title": "Uploaded"}}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/sappho/api/upload")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON)
        }

        let result = try await api.uploadAudiobook(
            fileData: Data([0x00]),
            fileName: "book.m4b",
            mimeType: "audio/mp4",
            title: nil,
            author: nil,
            narrator: nil,
            onProgress: { _ in }
        )
        XCTAssertEqual(result.audiobook?.id, 7)

        let paths = MockURLProtocol.capturedRequests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/sappho/api/upload"])
    }

    // MARK: - Helpers

    private func makeLoginUser(id: Int, username: String, isAdmin: Int) -> LoginUser {
        let json = """
        {"id": \(id), "username": "\(username)", "is_admin": \(isAdmin)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(LoginUser.self, from: json)
    }
}

/// Decodable struct to verify login request body in tests
private struct LoginRequestPayload: Codable {
    let username: String
    let password: String
}
