import UIKit
import AVFoundation
import GoogleCast

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure audio session for background playback
        configureAudioSession()

        // Configure Google Cast
        configureCast()

        return true
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func configureCast() {
        let options = GCKCastOptions(
            discoveryCriteria: GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        )
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)

        // Enable logger in debug
        #if DEBUG
        GCKLogger.sharedInstance().delegate = self
        #endif
    }

    // Handle background URL session events for downloads
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

// MARK: - GCKLoggerDelegate
extension AppDelegate: GCKLoggerDelegate {
    func logMessage(_ message: String, at level: GCKLoggerLevel, fromFunction function: String, location: String) {
        #if DEBUG
        print("GoogleCast: \(message)")
        #endif
    }
}
