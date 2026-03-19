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

        // Store credentials so API considers us authenticated
        let loginUser = makeLoginUser(id: 1, username: "test", isAdmin: 0)
        authRepo.store(serverURL: testServerURL, token: testToken, user: loginUser)

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
