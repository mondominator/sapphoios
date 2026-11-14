#if DEBUG
import Foundation

/// Launch states for UI tests, so they can drive real screens without a
/// server. Debug builds only; release builds never contain this.
enum UITestLaunch {
    /// Signed in to an unreachable server with a book loaded but paused,
    /// so the mini player shows in its paused state.
    static let pausedMiniPlayer = "-uiTestPausedMiniPlayer"

    @MainActor
    static func apply(authRepository: AuthRepository, audioPlayer: AudioPlayerService) {
        guard ProcessInfo.processInfo.arguments.contains(pausedMiniPlayer) else { return }
        // Port 9 (discard) refuses connections, so requests fail at once
        // and nothing answers 401 and signs the test out.
        authRepository.useInMemorySession(serverURL: URL(string: "http://127.0.0.1:9")!, token: "ui-test")
        audioPlayer.currentAudiobook = Audiobook(id: 1, title: "UI Test Book", author: "Test Author", duration: 600)
        audioPlayer.duration = 600
        audioPlayer.position = 2
    }
}
#endif
