import SwiftUI

/// Shown instead of the app when the server requires a new password
/// (`must_change_password`, e.g. an account an admin just created or reset).
///
/// The server answers 403 to every other route until the password changes,
/// and it revokes every token once it does, so on success the user signs in
/// again with the new password.
struct ChangePasswordRequiredView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.sapphoAPI) private var api

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.sapphoPrimary)
                        .accessibilityHidden(true)
                    Text("Choose a new password")
                        .font(.sapphoTitle)
                        .foregroundColor(.sapphoTextHigh)
                        .multilineTextAlignment(.center)
                    Text("Your server requires you to change your password before continuing.")
                        .font(.sapphoSubheadline)
                        .foregroundColor(.sapphoTextMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)

                VStack(spacing: 16) {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                        .textFieldStyle(SapphoTextFieldStyle())
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(SapphoTextFieldStyle())
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(SapphoTextFieldStyle())

                    Text("At least 8 characters, with an uppercase letter, a lowercase letter, a number and a symbol.")
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoTextMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoError)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }

                    Button {
                        Task { await changePassword() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSaving ? "Saving..." : "Change Password")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SapphoPrimaryButtonStyle())
                    .disabled(isSaving || !isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.6)

                    Button("Log Out") {
                        Task {
                            await audioPlayer.prepareForLogout()
                            authRepository.clear()
                        }
                    }
                    .foregroundColor(.sapphoTextMuted)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.sapphoBackground)
    }

    private var isFormValid: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty
    }

    private func changePassword() async {
        errorMessage = nil
        guard newPassword == confirmPassword else {
            errorMessage = "The new passwords don't match."
            return
        }
        guard let api else {
            errorMessage = "API not configured"
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await api.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
            // The server revokes every token on a password change. Go back to
            // the login screen (server and username stay filled in).
            authRepository.setMustChangePassword(false)
            authRepository.loginNotice = "Password changed. Sign in with your new password."
            authRepository.clearToken()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
