import SwiftUI

struct LoginView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.sapphoAPI) private var api

    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showPassword: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.sapphoPrimary)

                    Text("Sappho")
                        .font(.sapphoTitle)
                        .foregroundColor(.sapphoTextHigh)

                    Text("Audiobook Server")
                        .font(.sapphoSubheadline)
                        .foregroundColor(.sapphoTextMuted)
                }
                .padding(.top, 60)

                // Login Form
                VStack(spacing: 20) {
                    // Server URL
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoTextMuted)

                        TextField("https://your-server.com", text: $serverURL)
                            .textFieldStyle(SapphoTextFieldStyle())
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    // Username
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoTextMuted)

                        TextField("Username", text: $username)
                            .textFieldStyle(SapphoTextFieldStyle())
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    // Password
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoTextMuted)

                        HStack {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textContentType(.password)
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                            }

                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                    .foregroundColor(.sapphoTextMuted)
                            }
                        }
                        .padding()
                        .background(Color.sapphoSurface)
                        .cornerRadius(10)
                    }

                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoError)
                            .multilineTextAlignment(.center)
                    }

                    // Login Button
                    Button {
                        Task {
                            await login()
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isLoading ? "Connecting..." : "Login")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SapphoPrimaryButtonStyle())
                    .disabled(isLoading || !isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.6)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .background(Color.sapphoBackground)
        .onAppear {
            // Pre-fill server URL if previously stored
            if let stored = authRepository.serverURL {
                serverURL = stored.absoluteString
            }
        }
    }

    private var isFormValid: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    private func login() async {
        guard let url = URL(string: normalizeServerURL(serverURL)) else {
            errorMessage = "Invalid server URL"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            guard let api = api else {
                errorMessage = "API not configured"
                isLoading = false
                return
            }

            let response = try await api.login(serverURL: url, username: username, password: password)
            authRepository.store(serverURL: url, token: response.token, user: response.user)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func normalizeServerURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if no scheme provided
        if !normalized.contains("://") {
            normalized = "https://" + normalized
        }

        // Remove trailing slash
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }

        return normalized
    }
}

// MARK: - Text Field Style
struct SapphoTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.sapphoSurface)
            .cornerRadius(10)
            .foregroundColor(.sapphoTextHigh)
    }
}

#Preview {
    LoginView()
        .environment(AuthRepository())
}
