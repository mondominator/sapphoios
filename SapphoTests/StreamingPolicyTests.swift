import XCTest
import CoreMedia
@testable import Sappho

// MARK: - Choosing the mode

final class StreamingPolicyModeTests: XCTestCase {
    private let wifi = NetworkConditions.unmetered
    private let cellular = NetworkConditions(isCellular: true, isExpensive: true, isConstrained: false)
    private let hotspot = NetworkConditions(isCellular: false, isExpensive: true, isConstrained: false)
    private let lowDataMode = NetworkConditions(isCellular: false, isExpensive: false, isConstrained: true)

    private func mode(
        downloaded: Bool = false,
        network: NetworkConditions,
        dataSaver: Bool = false,
        codec: HLSCodecHint = .unknown,
        blocked: Bool = false
    ) -> StreamMode {
        StreamingPolicy.mode(isDownloaded: downloaded, network: network, dataSaver: dataSaver, codec: codec, hlsBlocked: blocked)
    }

    func testWifiKeepsProgressive() {
        XCTAssertEqual(mode(network: wifi), .progressive)
        XCTAssertEqual(mode(network: wifi, codec: .supported), .progressive)
    }

    func testCellularExpensiveAndConstrainedUseHLSSource() {
        XCTAssertEqual(mode(network: cellular), .hls(preferLow: false))
        XCTAssertEqual(mode(network: hotspot), .hls(preferLow: false))
        XCTAssertEqual(mode(network: lowDataMode), .hls(preferLow: false))
        XCTAssertEqual(mode(network: NetworkConditions(isCellular: true, isExpensive: false, isConstrained: false)), .hls(preferLow: false))
    }

    func testDataSaverUsesLowVariantOnAnyNetwork() {
        XCTAssertEqual(mode(network: wifi, dataSaver: true), .hls(preferLow: true))
        XCTAssertEqual(mode(network: cellular, dataSaver: true), .hls(preferLow: true))
    }

    func testDownloadedBookAlwaysPlaysTheFile() {
        XCTAssertEqual(mode(downloaded: true, network: cellular, dataSaver: true), .localFile)
        XCTAssertEqual(mode(downloaded: true, network: wifi), .localFile)
        XCTAssertEqual(mode(downloaded: true, network: cellular, codec: .unsupported), .localFile)
    }

    func testUnsupportedCodecNeverUsesHLS() {
        XCTAssertEqual(mode(network: cellular, codec: .unsupported), .progressive)
        XCTAssertEqual(mode(network: wifi, dataSaver: true, codec: .unsupported), .progressive)
    }

    func testBlockedAfterFailureUsesProgressive() {
        XCTAssertEqual(mode(network: cellular, blocked: true), .progressive)
        XCTAssertEqual(mode(network: wifi, dataSaver: true, blocked: true), .progressive)
    }

    func testCodecHintFromFilePath() {
        XCTAssertEqual(HLSCodecHint.from(filePath: "/audiobooks/A/B.m4b"), .supported)
        XCTAssertEqual(HLSCodecHint.from(filePath: "/audiobooks/A/B.M4A"), .supported)
        XCTAssertEqual(HLSCodecHint.from(filePath: "/x/y.mp4"), .supported)
        XCTAssertEqual(HLSCodecHint.from(filePath: "/x/y.mp3"), .unsupported)
        XCTAssertEqual(HLSCodecHint.from(filePath: "/x/y.flac"), .unsupported)
        XCTAssertEqual(HLSCodecHint.from(filePath: nil), .unknown)
        XCTAssertEqual(HLSCodecHint.from(filePath: ""), .unknown)
        XCTAssertEqual(HLSCodecHint.from(filePath: "/x/noext"), .unknown)
    }

    func testAudiobookDecodesFilePath() throws {
        let json = #"{"id":7,"title":"T","file_path":"/lib/T/T.mp3"}"#
        let book = try JSONDecoder().decode(Audiobook.self, from: Data(json.utf8))
        XCTAssertEqual(book.filePath, "/lib/T/T.mp3")
        XCTAssertEqual(book.withChapters([]).filePath, "/lib/T/T.mp3")
    }
}

// MARK: - URLs

final class StreamingPolicyURLTests: XCTestCase {
    private let base = URL(string: "https://sappho.example.com")!

    func testProgressiveURL() {
        XCTAssertEqual(StreamingPolicy.url(for: .progressive, baseURL: base, audiobookId: 42)?.absoluteString,
                       "https://sappho.example.com/api/audiobooks/42/stream")
    }

    func testHLSURL() {
        XCTAssertEqual(StreamingPolicy.url(for: .hls(preferLow: false), baseURL: base, audiobookId: 42)?.absoluteString,
                       "https://sappho.example.com/api/audiobooks/42/hls/master.m3u8")
    }

    func testDataSaverURLPrefersLow() {
        XCTAssertEqual(StreamingPolicy.url(for: .hls(preferLow: true), baseURL: base, audiobookId: 42)?.absoluteString,
                       "https://sappho.example.com/api/audiobooks/42/hls/master.m3u8?prefer=low")
    }

    func testNoTokenInAnyURL() {
        for mode in [StreamMode.progressive, .hls(preferLow: false), .hls(preferLow: true)] {
            let url = StreamingPolicy.url(for: mode, baseURL: base, audiobookId: 1)!
            XCTAssertFalse(url.absoluteString.contains("token"), "\(mode) must authenticate with the header")
        }
    }

    func testLocalFileHasNoRemoteURL() {
        XCTAssertNil(StreamingPolicy.url(for: .localFile, baseURL: base, audiobookId: 1))
    }

    func testServerURLWithPathPrefix() {
        let prefixed = URL(string: "https://example.com/sappho")!
        XCTAssertEqual(StreamingPolicy.url(for: .hls(preferLow: true), baseURL: prefixed, audiobookId: 3)?.absoluteString,
                       "https://example.com/sappho/api/audiobooks/3/hls/master.m3u8?prefer=low")
    }

    func testPeakBitRateCapsOnlyDataSaver() {
        XCTAssertEqual(StreamingPolicy.preferredPeakBitRate(for: .hls(preferLow: true)), StreamingPolicy.dataSaverPeakBitRate)
        XCTAssertGreaterThan(StreamingPolicy.dataSaverPeakBitRate, 0)
        XCTAssertEqual(StreamingPolicy.preferredPeakBitRate(for: .hls(preferLow: false)), 0)
        XCTAssertEqual(StreamingPolicy.preferredPeakBitRate(for: .progressive), 0)
    }

    func testSeeksAreExact() {
        // HLS with the default tolerance lands on a segment boundary; the same
        // position must resume at the same spot in both modes.
        XCTAssertEqual(SeekPolicy.toleranceBefore, .zero)
        XCTAssertEqual(SeekPolicy.toleranceAfter, .zero)
    }
}

// MARK: - Recovering from HLS failures

final class HLSRecoveryPolicyTests: XCTestCase {
    func testUnsupportedFallsBack() {
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .unsupported, failedVersion: nil, failedStatusCode: 415, reloadsSoFar: 0),
                       .fallBackToProgressive)
    }

    func testFileVersionChangedReloadsMaster() {
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "200-2"), failedVersion: "100-1", failedStatusCode: 404, reloadsSoFar: 0),
                       .reloadHLS)
    }

    func testSameVersionFailureFallsBack() {
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "100-1"), failedVersion: "100-1", failedStatusCode: 404, reloadsSoFar: 0),
                       .fallBackToProgressive)
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "100-1"), failedVersion: nil, failedStatusCode: nil, reloadsSoFar: 0),
                       .fallBackToProgressive)
    }

    func testUnattributed404ReloadsMaster() {
        // Measured on iOS: AVPlayer's error log carries no URI for a failed
        // segment, only "HTTP 404: File Not Found".
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "200-2"), failedVersion: nil, failedStatusCode: 404, reloadsSoFar: 0),
                       .reloadHLS)
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "200-2"), failedVersion: nil, failedStatusCode: 500, reloadsSoFar: 0),
                       .fallBackToProgressive)
    }

    func testExpiredTokenReloads() {
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "100-1"), failedVersion: "100-1", failedStatusCode: 401, reloadsSoFar: 0),
                       .reloadHLS)
    }

    func testProbeFailureFallsBack() {
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .failed(statusCode: nil), failedVersion: "100-1", failedStatusCode: 404, reloadsSoFar: 0),
                       .fallBackToProgressive)
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .failed(statusCode: 409), failedVersion: nil, failedStatusCode: 409, reloadsSoFar: 0),
                       .fallBackToProgressive)
    }

    func testReloadsAreBounded() {
        XCTAssertEqual(HLSRecoveryPolicy.action(probe: .available(fileVersion: "300-3"), failedVersion: "200-2", failedStatusCode: 404,
                                                reloadsSoFar: HLSRecoveryPolicy.maxReloads),
                       .fallBackToProgressive)
    }

    func testFileVersionFromURI() {
        XCTAssertEqual(HLSRecoveryPolicy.fileVersion(inURI: "https://s.example/api/audiobooks/5/hls/1234-1700000000000/source/seg-12.m4s"), "1234-1700000000000")
        XCTAssertEqual(HLSRecoveryPolicy.fileVersion(inURI: "https://s.example/api/audiobooks/5/hls/1234-17/low/index.m3u8"), "1234-17")
        XCTAssertNil(HLSRecoveryPolicy.fileVersion(inURI: "https://s.example/api/audiobooks/5/hls/master.m3u8"))
        XCTAssertNil(HLSRecoveryPolicy.fileVersion(inURI: "https://s.example/api/audiobooks/5/stream"))
        XCTAssertNil(HLSRecoveryPolicy.fileVersion(inURI: nil))
    }

    func testHTTPStatusFromErrorLog() {
        XCTAssertEqual(HLSRecoveryPolicy.httpStatus(comment: "HTTP 404: File Not Found", code: -12938), 404)
        XCTAssertEqual(HLSRecoveryPolicy.httpStatus(comment: "The operation couldn’t be completed. (CoreMediaErrorDomain error -12938 - HTTP 404: File Not Found)", code: -12938), 404)
        XCTAssertEqual(HLSRecoveryPolicy.httpStatus(comment: "HTTP 401: Unauthorized", code: -12937), 401)
        XCTAssertEqual(HLSRecoveryPolicy.httpStatus(comment: nil, code: 415), 415)
        XCTAssertNil(HLSRecoveryPolicy.httpStatus(comment: "Connection refused", code: -1004))
    }
}

// MARK: - Master probe (SapphoAPI)

final class HLSStubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String]))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, headers) = handler(request)
        if status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private func makeStubAPI(serverURL: URL = URL(string: "https://sappho.test")!) -> (SapphoAPI, AuthRepository) {
    let repo = AuthRepository()
    repo.clear()
    let user = try! JSONDecoder().decode(LoginUser.self, from: Data(#"{"id":1,"username":"u1","is_admin":0}"#.utf8))
    repo.store(serverURL: serverURL, token: "tok", refreshToken: nil, user: user)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [HLSStubProtocol.self]
    return (SapphoAPI(authRepository: repo, session: URLSession(configuration: config)), repo)
}

@MainActor
final class HLSProbeTests: XCTestCase {
    private var repo: AuthRepository?

    override func setUp() {
        super.setUp()
        HLSStubProtocol.handler = nil
        HLSStubProtocol.requests = []
    }

    override func tearDown() {
        repo?.clear()
        HLSStubProtocol.handler = nil
        HLSStubProtocol.requests = []
        super.tearDown()
    }

    func testAvailableReadsFileVersionAndSendsHeaderAuth() async {
        let (api, repo) = makeStubAPI()
        self.repo = repo
        HLSStubProtocol.handler = { _ in (200, ["X-File-Version": "99-123", "Content-Type": "application/vnd.apple.mpegurl"]) }
        let result = await api.probeHLSMaster(for: 8)
        XCTAssertEqual(result, .available(fileVersion: "99-123"))
        let request = HLSStubProtocol.requests.last
        XCTAssertEqual(request?.url?.absoluteString, "https://sappho.test/api/audiobooks/8/hls/master.m3u8")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testUnsupported() async {
        let (api, repo) = makeStubAPI()
        self.repo = repo
        HLSStubProtocol.handler = { _ in (415, [:]) }
        let result = await api.probeHLSMaster(for: 8)
        XCTAssertEqual(result, .unsupported)
    }

    func testOtherStatusAndNetworkFailure() async {
        let (api, repo) = makeStubAPI()
        self.repo = repo
        HLSStubProtocol.handler = { _ in (409, [:]) }
        let conflict = await api.probeHLSMaster(for: 8)
        XCTAssertEqual(conflict, .failed(statusCode: 409))
        HLSStubProtocol.handler = { _ in (0, [:]) }
        let offline = await api.probeHLSMaster(for: 8)
        XCTAssertEqual(offline, .failed(statusCode: nil))
    }
}

// MARK: - The player (phone and CarPlay) uses the choice

@MainActor
final class AudioPlayerStreamModeTests: XCTestCase {
    private var repo: AuthRepository?
    private var service: AudioPlayerService?
    /// Connection refused at once, so AVPlayer fails fast and offline.
    private let deadServer = URL(string: "http://127.0.0.1:9")!
    private let bookId = 9_870_001

    override func setUp() {
        super.setUp()
        HLSStubProtocol.handler = nil
        HLSStubProtocol.requests = []
        UserDefaults.standard.removeObject(forKey: StreamingPolicy.dataSaverKey)
    }

    override func tearDown() {
        service?.stop(syncProgress: false)
        service = nil
        repo?.clear()
        HLSStubProtocol.handler = nil
        UserDefaults.standard.removeObject(forKey: StreamingPolicy.dataSaverKey)
        UserDefaults.standard.removeObject(forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.removeObject(forKey: "lastPlayedPosition")
        super.tearDown()
    }

    private func makeService(network: NetworkConditions) -> AudioPlayerService {
        let (api, repo) = makeStubAPI(serverURL: deadServer)
        self.repo = repo
        let service = AudioPlayerService()
        service.configure(api: api)
        service.networkConditions = { network }
        self.service = service
        return service
    }

    private func book(filePath: String? = nil) -> Audiobook {
        Audiobook(id: bookId, title: "Streaming test", duration: 3600,
                  chapters: [Chapter(id: 1, audiobookId: bookId, chapterNumber: 1, startTime: 0, duration: 3600, title: "One")],
                  filePath: filePath)
    }

    func testCellularPlaysHLSMaster() async {
        HLSStubProtocol.handler = { _ in (500, [:]) }
        let service = makeService(network: NetworkConditions(isCellular: true, isExpensive: true, isConstrained: false))
        await service.play(audiobook: book(), startPosition: 0)
        XCTAssertEqual(service.streamMode, .hls(preferLow: false))
        XCTAssertEqual(service.streamURL?.absoluteString, "http://127.0.0.1:9/api/audiobooks/\(bookId)/hls/master.m3u8")
    }

    func testWifiPlaysProgressive() async {
        let service = makeService(network: .unmetered)
        await service.play(audiobook: book(), startPosition: 0)
        XCTAssertEqual(service.streamMode, .progressive)
        XCTAssertEqual(service.streamURL?.absoluteString, "http://127.0.0.1:9/api/audiobooks/\(bookId)/stream")
    }

    func testDataSaverPrefersLow() async {
        HLSStubProtocol.handler = { _ in (500, [:]) }
        UserDefaults.standard.set(true, forKey: StreamingPolicy.dataSaverKey)
        let service = makeService(network: .unmetered)
        await service.play(audiobook: book(), startPosition: 0)
        XCTAssertEqual(service.streamMode, .hls(preferLow: true))
        XCTAssertEqual(service.streamURL?.query, "prefer=low")
    }

    func testMP3BookStaysProgressiveOnCellular() async {
        let service = makeService(network: NetworkConditions(isCellular: true, isExpensive: true, isConstrained: false))
        await service.play(audiobook: book(filePath: "/lib/b/b.mp3"), startPosition: 0)
        XCTAssertEqual(service.streamMode, .progressive)
    }

    func testCarPlayStartUsesTheSameChoice() async {
        HLSStubProtocol.handler = { _ in (500, [:]) }
        let service = makeService(network: NetworkConditions(isCellular: true, isExpensive: true, isConstrained: false))
        let task = CarPlayPlaybackStarter.start(book(), downloaded: nil, player: service, showNowPlaying: {}, refreshTimeout: 0.1)
        await task.value
        XCTAssertEqual(service.streamMode, .hls(preferLow: false))
    }

    /// The master answers 415 (an MP3 the client couldn't tell from its
    /// metadata): the player continues on /stream at the same position.
    func testHLSFailureWith415FallsBackToProgressiveAtSamePosition() async throws {
        HLSStubProtocol.handler = { request in
            request.url?.path.hasSuffix("/hls/master.m3u8") == true ? (415, [:]) : (500, [:])
        }
        let service = makeService(network: NetworkConditions(isCellular: true, isExpensive: true, isConstrained: false))
        await service.play(audiobook: book(), startPosition: 1234)
        XCTAssertEqual(service.streamMode, .hls(preferLow: false))

        try await waitUntil(timeout: 20) { service.streamMode == .progressive }
        XCTAssertEqual(service.streamURL?.path, "/api/audiobooks/\(bookId)/stream")
        XCTAssertEqual(service.position, 1234, accuracy: 0.5)
        XCTAssertTrue(HLSStubProtocol.requests.contains { $0.url?.path.hasSuffix("/hls/master.m3u8") == true },
                      "the failure must be diagnosed by asking for the master")

        // Next play of the same book skips HLS without another round trip.
        service.stop(syncProgress: false)
        await service.play(audiobook: book(), startPosition: 0)
        XCTAssertEqual(service.streamMode, .progressive)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("condition not met within \(timeout) s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
