import XCTest
import AVFoundation
@testable import Sappho

/// Behavioural regression tests for the 2026-10-06 audit fixes.
///
/// Every test here drives code paths that also exist in the pre-fix app
/// (public service and API methods only), so this file compiles against the
/// old code too, where each test fails. That is the proof the tests detect
/// the bugs rather than merely passing.
@MainActor
final class AuditRegressionTests: XCTestCase {

    private var authRepo: AuthRepository!
    private var api: SapphoAPI!
    private let serverURL = URL(string: "https://sappho.test.com")!

    private let defaultsKeys = [
        "lastPlayedAudiobookId", "lastPlayedPosition", "pendingProgressSync",
        "pendingProgressByAccount", "localProgressByAccount", "rewindOnResume"
    ]

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        authRepo = AuthRepository()
        authRepo.clear()
        authRepo.store(serverURL: serverURL, token: "token-1", refreshToken: nil, user: makeLoginUser(id: 1))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        api = SapphoAPI(authRepository: authRepo, session: URLSession(configuration: config))
    }

    override func tearDown() async throws {
        authRepo.clear()
        MockURLProtocol.reset()
        defaultsKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        try await super.tearDown()
    }

    // MARK: - 1. A 403 must not log the user out

    func test403KeepsTheSession() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
             #"{"error":"Password change required","must_change_password":true}"#.data(using: .utf8)!)
        }

        do {
            _ = try await api.getRecentlyAdded()
            XCTFail("Should have thrown")
        } catch {}
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(authRepo.isAuthenticated, "403 means forbidden by policy, not logged out")
        XCTAssertEqual(authRepo.token, "token-1")
    }

    /// A 401 from an endpoint after the token was just refreshed is the
    /// endpoint's own answer (PUT /api/profile/password: "Current password is
    /// incorrect"), so typing a wrong current password must not log out.
    func testWrongCurrentPasswordDoesNotLogOut() async {
        authRepo.store(serverURL: serverURL, token: "token-1", refreshToken: "refresh-1", user: makeLoginUser(id: 1))
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.hasSuffix("api/auth/refresh") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                        #"{"token":"token-2","refreshToken":"refresh-2"}"#.data(using: .utf8)!)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    #"{"error":"Current password is incorrect"}"#.data(using: .utf8)!)
        }

        do {
            try await api.updatePassword(currentPassword: "wrong", newPassword: "N3w!password")
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual((error as? APIError)?.errorDescription, "Current password is incorrect")
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(authRepo.isAuthenticated)
    }

    // MARK: - Device name / app version headers

    func testRequestsCarryDeviceNameAndAppVersion() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        _ = try await api.getRecentlyAdded()

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let deviceName = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Device-Name"))
        XCTAssertFalse(deviceName.isEmpty)
        XCTAssertTrue(deviceName.allSatisfy { $0.isASCII }, "header values must be ASCII (percent-encoded)")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-App-Version"))
    }

    // MARK: - 2. Continue on the loaded book resumes, not restarts

    func testPlayingTheLoadedBookKeepsItsPosition() async {
        let player = AudioPlayerService()
        // The detail view's copy of the book: server position from when it opened.
        let staleCopy = makeBook(id: 42, position: 100, updatedAt: nil)
        player.currentAudiobook = staleCopy
        player.position = 3_700
        // What the app saved as it played.
        UserDefaults.standard.set(42, forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.set(3_700, forKey: "lastPlayedPosition")

        await player.play(audiobook: staleCopy)

        XCTAssertEqual(player.currentAudiobook?.id, 42)
        XCTAssertEqual(player.position, 3_700, accuracy: 1, "Continue must not jump back to the stale server position")
    }

    // MARK: - 4. Offline queue replays with isReplay

    func testPendingProgressIsReplayedWithIsReplay() async throws {
        // A queue entry as written by the previous build.
        UserDefaults.standard.set(["42": 500], forKey: "pendingProgressSync")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "{}".data(using: .utf8)!)
        }

        let player = AudioPlayerService()
        player.configure(api: api)
        player.syncPendingProgress()

        let request = try await waitForRequest { $0.url!.path.hasSuffix("audiobooks/42/progress") }
        let body = try XCTUnwrap(bodyJSON(of: request))
        XCTAssertEqual(body["position"] as? Int, 500)
        XCTAssertEqual(body["isReplay"] as? Bool, true, "replays must opt in to the server's forward-only guard")
    }

    // MARK: - 5. Restore prefers the newer local position

    func testRestorePrefersLocalPositionOverOlderServerPosition() async {
        UserDefaults.standard.set(42, forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.set(5_000, forKey: "lastPlayedPosition")
        MockURLProtocol.requestHandler = { request in
            let path = request.url!.path
            let body: String
            if path.hasSuffix("audiobooks/42") {
                body = #"{"id":42,"title":"Book","duration":36000,"progress":{"position":100,"completed":0,"updated_at":"2020-01-01 00:00:00"}}"#
            } else {
                body = "[]"
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body.data(using: .utf8)!)
        }

        let player = AudioPlayerService()
        player.configure(api: api)
        await player.restoreLastPlayed()

        XCTAssertEqual(player.currentAudiobook?.id, 42)
        XCTAssertEqual(player.position, 5_000, accuracy: 1, "an hour of offline listening must not be dropped")
    }

    // MARK: - 10. A paused book must not start after a phone call

    func testInterruptionEndDoesNotStartAPausedBook() {
        let player = AudioPlayerService()
        player.isPlaying = false

        postInterruption(.began)
        postInterruption(.ended, shouldResume: true)

        XCTAssertFalse(player.isPlaying, "paused before the call, so stay paused")
    }

    func testInterruptionEndWithoutShouldResumeStaysPaused() {
        let player = AudioPlayerService()
        player.isPlaying = true

        postInterruption(.began)
        XCTAssertFalse(player.isPlaying)
        postInterruption(.ended, shouldResume: false)

        XCTAssertFalse(player.isPlaying, "another app took over audio; don't take it back")
    }

    // MARK: - 12. Unplugging headphones, then a route reconfiguration

    func testRouteReconfigurationAfterUnplugDoesNotResume() {
        let player = AudioPlayerService()
        player.isPlaying = true

        postRouteChange(.oldDeviceUnavailable)
        XCTAssertFalse(player.isPlaying)
        postRouteChange(.routeConfigurationChange)

        XCTAssertFalse(player.isPlaying, "must not start playing through the speaker by itself")
    }

    // MARK: - 3. A failed download is not saved as a book

    func testErrorResponseIsNotSavedAsADownload() throws {
        let id = 987_654
        let manager = DownloadManager.shared
        defer { manager.removeDownload(audiobookId: id) }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try #"{"error":"Invalid or expired token"}"#.data(using: .utf8)!.write(to: temp)
        let response = HTTPURLResponse(url: serverURL, statusCode: 401, httpVersion: nil, headerFields: nil)
        let task = FakeDownloadTask(response: response, id: id)

        manager.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: temp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertNil(manager.localURL(for: id), "a 401 body must not become <id>.m4b")
        if case .failed = manager.downloads[id] {} else {
            XCTFail("expected .failed, got \(String(describing: manager.downloads[id]))")
        }
    }

    func testValidAudioDownloadIsSaved() throws {
        let id = 987_655
        let manager = DownloadManager.shared
        defer { manager.removeDownload(audiobookId: id) }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var audio = Data([0x00, 0x00, 0x00, 0x20]) + "ftypM4B ".data(using: .ascii)!
        audio.append(Data(count: 200_000))
        try audio.write(to: temp)
        let response = HTTPURLResponse(url: serverURL, statusCode: 200, httpVersion: nil, headerFields: nil)
        let task = FakeDownloadTask(response: response, id: id)

        manager.urlSession(URLSession.shared, downloadTask: task, didFinishDownloadingTo: temp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertNotNil(manager.localURL(for: id))
    }

    // MARK: - Helpers

    private func makeLoginUser(id: Int) -> LoginUser {
        try! JSONDecoder().decode(LoginUser.self, from: #"{"id":\#(id),"username":"u\#(id)","is_admin":0}"#.data(using: .utf8)!)
    }

    private func makeBook(id: Int, position: Int, updatedAt: String?) -> Audiobook {
        let timestamp = updatedAt.map { #","updated_at":"\#($0)""# } ?? ""
        let json = #"{"id":\#(id),"title":"Book","duration":36000,"progress":{"position":\#(position),"completed":0\#(timestamp)}}"#
        return try! JSONDecoder().decode(Audiobook.self, from: json.data(using: .utf8)!)
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if type == .ended {
            let options: AVAudioSession.InterruptionOptions = shouldResume ? .shouldResume : []
            info[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func postRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func waitForRequest(timeout: TimeInterval = 3, matching predicate: (URLRequest) -> Bool) async throws -> URLRequest {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = MockURLProtocol.capturedRequests.first(where: predicate) {
                return match
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("no matching request within \(timeout)s")
        throw URLError(.timedOut)
    }

    private func bodyJSON(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(buffer, count: read)
            }
            data = collected
        }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// A download task whose response and description the test controls.
private final class FakeDownloadTask: URLSessionDownloadTask, @unchecked Sendable {
    private let fakeResponse: URLResponse?
    private let fakeDescription: String

    init(response: URLResponse?, id: Int) {
        self.fakeResponse = response
        self.fakeDescription = String(id)
        super.init()
    }

    override var response: URLResponse? { fakeResponse }

    override var taskDescription: String? {
        get { fakeDescription }
        set {}
    }
}
