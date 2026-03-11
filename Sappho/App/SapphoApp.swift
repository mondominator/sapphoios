import SwiftUI

@main
struct SapphoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authRepository: AuthRepository
    @State private var api: SapphoAPI
    @State private var audioPlayer = AudioPlayerService()

    init() {
        let repo = AuthRepository()
        _authRepository = State(initialValue: repo)
        _api = State(initialValue: SapphoAPI(authRepository: repo))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authRepository)
                .environment(audioPlayer)
                .environment(\.sapphoAPI, api)
                .preferredColorScheme(.dark)
                .onAppear {
                    audioPlayer.configure(api: api)
                    DownloadManager.shared.configure(api: api)
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
