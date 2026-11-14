#if DEBUG
import Foundation

/// Launch states for UI tests, so they can drive real screens without a
/// server. Debug builds only; release builds never contain this.
enum UITestLaunch {
    /// Signed in to an unreachable server with a book loaded but paused,
    /// so the mini player shows in its paused state.
    static let pausedMiniPlayer = "-uiTestPausedMiniPlayer"

    /// Signed in to a fake library served in-process (`UITestLibraryFixture`):
    /// 60 authors, one book each.
    static let libraryFixture = "-uiTestLibraryFixture"

    @MainActor
    static func apply(authRepository: AuthRepository, audioPlayer: AudioPlayerService) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(pausedMiniPlayer) {
            // Port 9 (discard) refuses connections, so requests fail at once
            // and nothing answers 401 and signs the test out.
            authRepository.useInMemorySession(serverURL: URL(string: "http://127.0.0.1:9")!, token: "ui-test")
            audioPlayer.currentAudiobook = Audiobook(id: 1, title: "UI Test Book", author: "Test Author", duration: 600)
            audioPlayer.duration = 600
            audioPlayer.position = 2
        } else if arguments.contains(libraryFixture) {
            URLProtocol.registerClass(UITestLibraryFixture.self)
            authRepository.useInMemorySession(serverURL: URL(string: "http://\(UITestLibraryFixture.host)")!, token: "ui-test")
        }
    }
}

/// Answers the library requests a UI test needs; every other request fails
/// as if the server were down (never a 401, which would sign the test out).
final class UITestLibraryFixture: URLProtocol {
    static let host = "sappho.uitest"
    static let authorNames = (1...60).map { String(format: "Author %02d", $0) }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let body = Self.body(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(for url: URL) -> Data? {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let json: Any
        switch url.path {
        case "/api/audiobooks/meta/authors":
            json = authorNames.map { ["author": $0, "book_count": 1, "cover_ids": [String]()] as [String: Any] }
        case "/api/audiobooks":
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
            let books: [[String: Any]]
            if offset == 0, let author = query.first(where: { $0.name == "author" })?.value,
               let index = authorNames.firstIndex(of: author) {
                books = [["id": index + 1, "title": "Book by \(author)", "author": author, "duration": 3600]]
            } else {
                books = []
            }
            json = ["audiobooks": books, "total": books.count]
        default:
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: json)
    }
}
#endif
