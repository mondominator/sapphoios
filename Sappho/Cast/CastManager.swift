import Foundation

// TODO: Add Google Cast SDK via CocoaPods for Chromecast support
// The SDK doesn't have official SPM support, so it needs to be added via:
// 1. Add Podfile with: pod 'google-cast-sdk', '~> 4.8'
// 2. Run: pod install
// 3. Open .xcworkspace instead of .xcodeproj

@Observable
class CastManager: NSObject {
    static let shared = CastManager()

    var isCastAvailable: Bool = false
    var isCasting: Bool = false
    var castDeviceName: String?
    var castPosition: TimeInterval = 0

    private var currentAudiobook: Audiobook?
    private var api: SapphoAPI?

    override init() {
        super.init()
        // Chromecast initialization would go here
    }

    func configure(api: SapphoAPI) {
        self.api = api
    }

    // MARK: - Cast Controls (stubs until SDK is added)

    func castAudiobook(_ audiobook: Audiobook, position: TimeInterval = 0) {
        // Will be implemented when Google Cast SDK is added
        print("Chromecast not available - SDK not integrated")
    }

    func play() {
        // Stub
    }

    func pause() {
        // Stub
    }

    func stop() {
        currentAudiobook = nil
    }

    func seek(to position: TimeInterval) {
        // Stub
    }

    func setPlaybackRate(_ rate: Float) {
        // Stub
    }

    func endSession() {
        // Stub
    }
}
