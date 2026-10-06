import SwiftUI

struct RootView: View {
    @Environment(AuthRepository.self) private var authRepository

    var body: some View {
        Group {
            if authRepository.isAuthenticated && authRepository.mustChangePassword {
                ChangePasswordRequiredView()
            } else if authRepository.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authRepository.isAuthenticated)
        .animation(.easeInOut, value: authRepository.mustChangePassword)
    }
}

#Preview {
    RootView()
        .environment(AuthRepository())
}
