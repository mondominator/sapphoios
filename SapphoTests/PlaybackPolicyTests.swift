import XCTest
@testable import Sappho

/// Unit tests for the pure decision rules behind the audit fixes.
final class PlaybackPolicyTests: XCTestCase {

    // MARK: - AuthFailurePolicy (403 handling)

    func test403NeverClearsTheSession() {
        XCTAssertFalse(AuthFailurePolicy.shouldClearSession(statusCode: 403, retriedWithFreshToken: false))
        XCTAssertFalse(AuthFailurePolicy.shouldClearSession(statusCode: 403, retriedWithFreshToken: true))
    }

    func test401ClearsUnlessTheTokenWasJustRefreshed() {
        XCTAssertTrue(AuthFailurePolicy.shouldClearSession(statusCode: 401, retriedWithFreshToken: false))
        XCTAssertFalse(AuthFailurePolicy.shouldClearSession(statusCode: 401, retriedWithFreshToken: true))
    }

    func testOtherErrorsNeverClearTheSession() {
        for status in [400, 404, 409, 500, 503] {
            XCTAssertFalse(AuthFailurePolicy.shouldClearSession(statusCode: status, retriedWithFreshToken: false), "\(status)")
        }
    }

    func testMustChangePasswordIsRecognised() {
        let body = #"{"error":"Password change required","must_change_password":true}"#.data(using: .utf8)!
        XCTAssertTrue(AuthFailurePolicy.isPasswordChangeRequired(statusCode: 403, body: body))
        XCTAssertFalse(AuthFailurePolicy.isPasswordChangeRequired(statusCode: 401, body: body))
        let admin = #"{"error":"Admin access required"}"#.data(using: .utf8)!
        XCTAssertFalse(AuthFailurePolicy.isPasswordChangeRequired(statusCode: 403, body: admin))
        XCTAssertFalse(AuthFailurePolicy.isPasswordChangeRequired(statusCode: 403, body: Data()))
    }

    // MARK: - PlaybackCompletionPolicy (finished threshold)

    func testEndNearTheKnownDurationIsAGenuineFinish() {
        XCTAssertTrue(PlaybackCompletionPolicy.isGenuineEnd(position: 36_000, knownDuration: 36_000))
        XCTAssertTrue(PlaybackCompletionPolicy.isGenuineEnd(position: 35_950, knownDuration: 36_000))
        XCTAssertTrue(PlaybackCompletionPolicy.isGenuineEnd(position: 35_940, knownDuration: 36_000))
    }

    func testEarlyEndIsNotAFinish() {
        // Part 1 of a 10-hour multi-file book ends at 1 hour.
        XCTAssertFalse(PlaybackCompletionPolicy.isGenuineEnd(position: 3_600, knownDuration: 36_000))
        XCTAssertFalse(PlaybackCompletionPolicy.isGenuineEnd(position: 35_900, knownDuration: 36_000))
    }

    func testUnknownDurationIsNeverAFinish() {
        XCTAssertFalse(PlaybackCompletionPolicy.isGenuineEnd(position: 3_600, knownDuration: nil))
        XCTAssertFalse(PlaybackCompletionPolicy.isGenuineEnd(position: 3_600, knownDuration: 0))
    }

    func testKnownDurationComesFromTheServerNotTheFile() {
        XCTAssertEqual(PlaybackCompletionPolicy.knownDuration(bookDuration: 36_000, chapters: nil), 36_000)
        let chapters = [
            Chapter(id: 1, audiobookId: 1, chapterNumber: 1, startTime: 0, duration: 1_000, title: nil),
            Chapter(id: 2, audiobookId: 1, chapterNumber: 2, startTime: 1_000, duration: 500, title: nil)
        ]
        XCTAssertEqual(PlaybackCompletionPolicy.knownDuration(bookDuration: nil, chapters: chapters), 1_500)
        XCTAssertNil(PlaybackCompletionPolicy.knownDuration(bookDuration: nil, chapters: nil))
    }

    // MARK: - ProgressReconciler (newer wins)

    private let serverStamp = "2026-10-06 12:00:00" // UTC

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testNewerLocalPositionWins() {
        let local = LocalProgress(position: 5_000, updatedAt: date("2026-10-06T13:00:00Z"))
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 100, serverUpdatedAt: serverStamp, local: local), 5_000)
    }

    func testNewerServerPositionWinsEvenWhenItIsEarlier() {
        // Another device rewound since this device last saved.
        let local = LocalProgress(position: 5_000, updatedAt: date("2026-10-06T11:00:00Z"))
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 100, serverUpdatedAt: serverStamp, local: local), 100)
    }

    func testServerTimestampIsUTC() {
        // 12:30Z local vs 12:00 server: local is newer only if the server
        // string is read as UTC.
        let local = LocalProgress(position: 7, updatedAt: date("2026-10-06T12:30:00Z"))
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 9, serverUpdatedAt: serverStamp, local: local), 7)
    }

    func testMissingDataFallsBackSensibly() {
        let local = LocalProgress(position: 400, updatedAt: Date())
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: nil, serverUpdatedAt: nil, local: local), 400)
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 300, serverUpdatedAt: serverStamp, local: nil), 300)
        // No usable server timestamp: the further position.
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 300, serverUpdatedAt: nil, local: local), 400)
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 900, serverUpdatedAt: "garbage", local: local), 900)
        // Pre-1.0.1 untimed local position.
        XCTAssertEqual(ProgressReconciler.resolve(serverPosition: 300, serverUpdatedAt: serverStamp, local: nil, untimedLocal: 800), 800)
    }

    func testParsesISOTimestamps() {
        XCTAssertNotNil(ProgressReconciler.parseServerTimestamp("2026-10-06T12:00:00Z"))
        XCTAssertNotNil(ProgressReconciler.parseServerTimestamp("2026-10-06T12:00:00.123Z"))
        XCTAssertNil(ProgressReconciler.parseServerTimestamp(nil))
    }

    // MARK: - InterruptionPolicy / PlayRequestPolicy

    func testInterruptionResumeNeedsBothSignals() {
        XCTAssertTrue(InterruptionPolicy.shouldResume(systemSaysShouldResume: true, wasPlaying: true))
        XCTAssertFalse(InterruptionPolicy.shouldResume(systemSaysShouldResume: true, wasPlaying: false))
        XCTAssertFalse(InterruptionPolicy.shouldResume(systemSaysShouldResume: false, wasPlaying: true))
        XCTAssertFalse(InterruptionPolicy.shouldResume(systemSaysShouldResume: false, wasPlaying: false))
    }

    func testPlayOnTheLoadedBookResumes() {
        XCTAssertTrue(PlayRequestPolicy.shouldResumeLoadedBook(loadedBookId: 42, requestedBookId: 42, explicitStart: nil))
        XCTAssertFalse(PlayRequestPolicy.shouldResumeLoadedBook(loadedBookId: 42, requestedBookId: 42, explicitStart: 600))
        XCTAssertFalse(PlayRequestPolicy.shouldResumeLoadedBook(loadedBookId: 7, requestedBookId: 42, explicitStart: nil))
        XCTAssertFalse(PlayRequestPolicy.shouldResumeLoadedBook(loadedBookId: nil, requestedBookId: 42, explicitStart: nil))
    }

    // MARK: - DownloadValidator

    func testOnly200And206AreAccepted() {
        XCTAssertTrue(DownloadValidator.validateResponse(statusCode: 200).isValid)
        XCTAssertTrue(DownloadValidator.validateResponse(statusCode: 206).isValid)
        for status in [401, 403, 404, 409, 500] {
            XCTAssertFalse(DownloadValidator.validateResponse(statusCode: status).isValid, "\(status)")
        }
        XCTAssertFalse(DownloadValidator.validateResponse(statusCode: nil).isValid)
    }

    func testErrorBodiesAndTinyFilesAreRejected() {
        let json = #"{"error":"Invalid or expired token"}"#.data(using: .utf8)!
        XCTAssertFalse(DownloadValidator.validateFile(size: Int64(json.count), expectedLength: nil, leadingBytes: json).isValid)
        // Even a large JSON/HTML body is not audio.
        XCTAssertFalse(DownloadValidator.validateFile(size: 500_000, expectedLength: nil, leadingBytes: Data("<html>".utf8)).isValid)
        let audio = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        XCTAssertFalse(DownloadValidator.validateFile(size: 1_000, expectedLength: nil, leadingBytes: audio).isValid)
        XCTAssertTrue(DownloadValidator.validateFile(size: 50_000_000, expectedLength: nil, leadingBytes: audio).isValid)
    }

    func testTruncatedTransferIsRejected() {
        let audio = Data([0x49, 0x44, 0x33]) // "ID3"
        XCTAssertFalse(DownloadValidator.validateFile(size: 40_000_000, expectedLength: 50_000_000, leadingBytes: audio).isValid)
        XCTAssertTrue(DownloadValidator.validateFile(size: 50_000_000, expectedLength: 50_000_000, leadingBytes: audio).isValid)
    }

    func testShortAudioIsRejected() {
        XCTAssertFalse(DownloadValidator.validateDuration(actual: 3_600, expected: 36_000).isValid)
        XCTAssertTrue(DownloadValidator.validateDuration(actual: 35_990, expected: 36_000).isValid)
        // An MP3 whose length AVFoundation estimates a few percent short is kept.
        XCTAssertTrue(DownloadValidator.validateDuration(actual: 34_500, expected: 36_000).isValid)
        XCTAssertFalse(DownloadValidator.validateDuration(actual: 30_000, expected: 36_000).isValid)
        XCTAssertTrue(DownloadValidator.validateDuration(actual: nil, expected: 36_000).isValid)
        XCTAssertTrue(DownloadValidator.validateDuration(actual: 3_600, expected: nil).isValid)
    }

    func testStalenessUsesTheRecordedServerSize() {
        // Recorded at download time and unchanged: fresh, even if the DB value
        // differs from the bytes on disk.
        XCTAssertFalse(DownloadValidator.isStale(recordedServerSize: 100, localSize: 98, currentServerSize: 100))
        // Server file replaced or merged.
        XCTAssertTrue(DownloadValidator.isStale(recordedServerSize: 100, localSize: 100, currentServerSize: 250))
        // Old download (nothing recorded): part 1 of a multi-file book vs the summed size.
        XCTAssertTrue(DownloadValidator.isStale(recordedServerSize: nil, localSize: 100, currentServerSize: 250))
        XCTAssertFalse(DownloadValidator.isStale(recordedServerSize: nil, localSize: 250, currentServerSize: 250))
        // Server size unknown: can't tell, keep it.
        XCTAssertFalse(DownloadValidator.isStale(recordedServerSize: 100, localSize: 100, currentServerSize: nil))
    }

    func testStalenessFallsBackToETagThenLength() {
        XCTAssertTrue(DownloadValidator.isStale(recordedETag: "\"1-2\"", localSize: 1, streamETag: "\"3-4\"", streamLength: 1))
        XCTAssertFalse(DownloadValidator.isStale(recordedETag: "\"1-2\"", localSize: 1, streamETag: "\"1-2\"", streamLength: 9))
        XCTAssertTrue(DownloadValidator.isStale(recordedETag: nil, localSize: 100, streamETag: "\"x\"", streamLength: 250))
        XCTAssertFalse(DownloadValidator.isStale(recordedETag: nil, localSize: 100, streamETag: nil, streamLength: nil))
    }

    // MARK: - ProgressStore (per-account queue)

    func testQueueIsScopedToTheAccount() {
        let defaults = UserDefaults(suiteName: "ProgressStoreTests-\(UUID().uuidString)")!
        let store = ProgressStore(defaults: defaults)
        store.savePending(account: "https://a|1", audiobookId: 42, position: 500)

        XCTAssertEqual(store.pending(account: "https://a|1"), [42: 500])
        XCTAssertTrue(store.pending(account: "https://a|2").isEmpty, "user B must not see user A's queue")
        XCTAssertTrue(store.pending(account: "https://b|1").isEmpty, "another server must not see it either")

        store.clear(account: "https://a|1")
        XCTAssertTrue(store.pending(account: "https://a|1").isEmpty, "logout clears the queue")
    }

    func testQueueKeepsTheLatestPositionAndRemovesEntries() {
        let defaults = UserDefaults(suiteName: "ProgressStoreTests-\(UUID().uuidString)")!
        let store = ProgressStore(defaults: defaults)
        store.savePending(account: "acct", audiobookId: 1, position: 100)
        store.savePending(account: "acct", audiobookId: 1, position: 300)
        store.savePending(account: "acct", audiobookId: 2, position: 200)
        store.removePending(account: "acct", audiobookId: 1)
        store.removePending(account: "acct", audiobookId: 99)
        XCTAssertEqual(store.pending(account: "acct"), [2: 200])
    }

    func testLegacyQueueMigratesToTheSignedInAccountOnly() {
        let defaults = UserDefaults(suiteName: "ProgressStoreTests-\(UUID().uuidString)")!
        defaults.set(["42": 500], forKey: ProgressStore.legacyPendingKey)
        let store = ProgressStore(defaults: defaults)

        store.migrateLegacyPending(to: "acct")
        XCTAssertEqual(store.pending(account: "acct"), [42: 500])
        XCTAssertNil(defaults.dictionary(forKey: ProgressStore.legacyPendingKey))

        defaults.set(["7": 70], forKey: ProgressStore.legacyPendingKey)
        store.migrateLegacyPending(to: nil)
        XCTAssertNil(defaults.dictionary(forKey: ProgressStore.legacyPendingKey), "signed out: dropped, not kept for the next account")
        XCTAssertEqual(store.pending(account: "acct"), [42: 500])
    }

    func testLocalProgressRoundTrips() {
        let defaults = UserDefaults(suiteName: "ProgressStoreTests-\(UUID().uuidString)")!
        let store = ProgressStore(defaults: defaults)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        store.saveLocal(account: "acct", audiobookId: 5, position: 1234, at: when)
        XCTAssertEqual(store.localProgress(account: "acct", audiobookId: 5), LocalProgress(position: 1234, updatedAt: when))
        XCTAssertNil(store.localProgress(account: "other", audiobookId: 5))
    }

    // MARK: - ClientInfo

    func testDeviceNameIsPercentEncodedToASCII() {
        let encoded = ClientInfo.encodeHeaderValue("Mondo\u{2019}s iPhone")
        XCTAssertEqual(encoded, "Mondo%E2%80%99s iPhone")
        XCTAssertEqual(ClientInfo.encodeHeaderValue("100% iPad"), "100%25 iPad")
        XCTAssertEqual(ClientInfo.encodeHeaderValue("Plain-Name_1.0"), "Plain-Name_1.0")
    }
}

/// The must_change_password flow at the API layer.
final class MustChangePasswordTests: XCTestCase {
    private var authRepo: AuthRepository!
    private var api: SapphoAPI!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        authRepo = AuthRepository()
        authRepo.clear()
        let user = try! JSONDecoder().decode(LoginUser.self, from: #"{"id":3,"username":"new","is_admin":0}"#.data(using: .utf8)!)
        authRepo.store(serverURL: URL(string: "https://sappho.test.com")!, token: "t", refreshToken: nil, user: user)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        api = SapphoAPI(authRepository: authRepo, session: URLSession(configuration: config))
    }

    override func tearDown() {
        authRepo.clear()
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testForbiddenPasswordGateRaisesTheFlagAndKeepsTheSession() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
             #"{"error":"Password change required","must_change_password":true}"#.data(using: .utf8)!)
        }
        XCTAssertFalse(authRepo.mustChangePassword)

        _ = try? await api.getInProgress()

        XCTAssertTrue(authRepo.mustChangePassword)
        XCTAssertTrue(authRepo.isAuthenticated)
    }

    func testAdminOnly403DoesNotRaiseTheFlag() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
             #"{"error":"Admin access required"}"#.data(using: .utf8)!)
        }
        _ = try? await api.getUsers()
        XCTAssertFalse(authRepo.mustChangePassword)
        XCTAssertTrue(authRepo.isAuthenticated)
    }

    func testFlagFromLoginPersistsAndClearsOnLogout() {
        let user = try! JSONDecoder().decode(LoginUser.self, from: #"{"id":3,"username":"new","is_admin":0}"#.data(using: .utf8)!)
        authRepo.store(serverURL: URL(string: "https://sappho.test.com")!, token: "t", refreshToken: nil, user: user, mustChangePassword: true)
        XCTAssertTrue(AuthRepository().mustChangePassword, "a relaunch must still show the change-password screen")
        XCTAssertEqual(authRepo.accountKey, "https://sappho.test.com|3")

        authRepo.clear()
        XCTAssertFalse(AuthRepository().mustChangePassword)
        XCTAssertNil(authRepo.accountKey)
    }
}
