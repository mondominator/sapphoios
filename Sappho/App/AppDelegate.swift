import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Audio session is configured by AudioPlayerService.setupAudioSession()
        // which sets .playback category with .longFormAudio policy.
        return true
    }

    // Handle background URL session events for downloads
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        // iOS relaunched us to deliver finished transfers. Store the handler,
        // then make sure the background session (and its delegate) exists, or
        // the events are never delivered and the handler never called.
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
        DownloadManager.shared.reattachSession()
    }
}
