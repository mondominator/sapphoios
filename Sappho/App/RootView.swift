import SwiftUI

struct RootView: View {
    @Environment(AuthRepository.self) private var authRepository

    var body: some View {
        Group {
            if authRepository.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authRepository.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environment(AuthRepository())
}
