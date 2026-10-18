import Intents
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Audio session is configured by AudioPlayerService.setupAudioSession()
        // which sets .playback category with .longFormAudio policy.

        // Siri ("play <book> on Sappho", on the phone or in the car) needs the
        // user's permission once; asked on the phone, since CarPlay can't.
        if INPreferences.siriAuthorizationStatus() == .notDetermined {
            INPreferences.requestSiriAuthorization { _ in }
        }
        return true
    }

    // MARK: - Siri

    /// Siri asks the app itself (no Intents extension) to resolve "play X".
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? PlayMediaIntentHandler.shared : nil
    }

    /// The resolved book, handed back in-app: start it the way a CarPlay tap
    /// does (immediately, from what the device has; the server copy after).
    func application(
        _ application: UIApplication,
        handle intent: INIntent,
        completionHandler: @escaping (INIntentResponse) -> Void
    ) {
        guard let intent = intent as? INPlayMediaIntent else {
            completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
            return
        }
        Task { @MainActor in
            guard let book = await PlayMediaIntentHandler.shared.book(for: intent),
                  let player = ServiceLocator.shared.audioPlayer else {
                completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))
                return
            }
            CarPlayPlaybackStarter.start(
                book,
                downloaded: DownloadManager.shared.cachedMeta[book.id]?.toAudiobook(),
                player: player,
                showNowPlaying: {}
            )
            completionHandler(INPlayMediaIntentResponse(code: .success, userActivity: nil))
        }
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
