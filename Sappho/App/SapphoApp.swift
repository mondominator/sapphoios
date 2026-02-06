import SwiftUI

@main
struct SapphoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authRepository = AuthRepository()
    @State private var api: SapphoAPI?
    @State private var audioPlayer = AudioPlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authRepository)
                .environment(audioPlayer)
                .onAppear {
                    if api == nil {
                        api = SapphoAPI(authRepository: authRepository)
                    }
                }
                .environment(\.sapphoAPI, api)
                .preferredColorScheme(.dark)
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
