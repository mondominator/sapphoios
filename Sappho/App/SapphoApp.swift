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

        // Populate ServiceLocator so non-SwiftUI classes (e.g. CarPlaySceneDelegate) can access services
        ServiceLocator.shared.api = apiInstance
        ServiceLocator.shared.audioPlayer = playerInstance
        ServiceLocator.shared.authRepository = repo
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
                    audioPlayer.configure(api: api)
                    DownloadManager.shared.configure(api: api)
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
