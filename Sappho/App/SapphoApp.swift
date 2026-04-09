import SwiftUI

@main
struct SapphoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authRepository: AuthRepository
    @State private var api: SapphoAPI
    @State private var audioPlayer: AudioPlayerService

    init() {
        let repo = AuthRepository()
        let apiInstance = SapphoAPI(authRepository: repo)
        let playerInstance = AudioPlayerService()
        _authRepository = State(initialValue: repo)
        _api = State(initialValue: apiInstance)
        _audioPlayer = State(initialValue: playerInstance)

        // Configure the player's API reference eagerly so it's ready
        // before any caller (including CarPlay's didConnect, which can
        // fire before the SwiftUI view appears) tries to stream audio.
        // Previously this lived in the view's .task modifier, which
        // only runs when the SwiftUI view renders its first frame —
        // if the phone screen is off and CarPlay is the only active
        // scene, .task never fires and playBook() silently fails
        // because audioPlayer.api is nil.
        playerInstance.configure(api: apiInstance)
        DownloadManager.shared.configure(api: apiInstance)

        // Populate ServiceLocator so non-SwiftUI classes (e.g. CarPlaySceneDelegate) can access services
        ServiceLocator.shared.configure(api: apiInstance, audioPlayer: playerInstance, authRepository: repo)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authRepository)
                .environment(audioPlayer)
                .environment(\.sapphoAPI, api)
                .preferredColorScheme(.dark)
                .task {
                    // configure(api:) already ran in init() so CarPlay
                    // has access from the start. Only restoreLastPlayed
                    // needs to be async and tied to the view lifecycle.
                    if authRepository.isAuthenticated {
                        await audioPlayer.restoreLastPlayed()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                audioPlayer.handleAppDidBecomeActive()
            }
        }
    }
}

// Environment key for SapphoAPI
private struct SapphoAPIKey: EnvironmentKey {
    static let defaultValue: SapphoAPI? = nil
}

extension EnvironmentValues {
    var sapphoAPI: SapphoAPI? {
        get { self[SapphoAPIKey.self] }
        set { self[SapphoAPIKey.self] = newValue }
    }
}
