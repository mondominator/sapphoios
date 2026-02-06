import SwiftUI

struct ProfileView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.sapphoAPI) private var api

    @State private var stats: UserStats?
    @State private var isLoading = true
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // User Info Card
                    if let user = authRepository.currentUser {
                        VStack(spacing: 16) {
                            // Avatar
                            AsyncImage(url: api?.avatarURL()) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.sapphoSurface)
                                    .overlay(
                                        Text(String(user.username?.prefix(1).uppercased() ?? "?"))
                                            .font(.sapphoTitle)
                                            .foregroundColor(.sapphoTextMuted)
                                    )
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())

                            // Name
                            Text(user.displayName ?? user.username ?? "User")
                                .font(.sapphoHeadline)
                                .foregroundColor(.sapphoTextHigh)

                            // Email
                            if let email = user.email {
                                Text(email)
                                    .font(.sapphoCaption)
                                    .foregroundColor(.sapphoTextMuted)
                            }

                            // Admin badge
                            if user.isAdminUser {
                                Text("Admin")
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.sapphoPrimary.opacity(0.2))
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.vertical, 24)
                    }

                    // Stats
                    if let stats = stats {
                        VStack(spacing: 16) {
                            Text("Listening Stats")
                                .font(.sapphoHeadline)
                                .foregroundColor(.sapphoTextHigh)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                StatCard(title: "Books Started", value: "\(stats.booksStarted)")
                                StatCard(title: "Books Completed", value: "\(stats.booksCompleted)")
                                StatCard(title: "Listen Time", value: formatDuration(stats.totalListenTime))
                                StatCard(title: "Current Streak", value: "\(stats.currentStreak) days")
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Settings Links
                    VStack(spacing: 0) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            SettingsRow(icon: "gear", title: "Settings")
                        }

                        Divider()
                            .background(Color.sapphoSurface)

                        NavigationLink {
                            DownloadsView()
                        } label: {
                            SettingsRow(icon: "arrow.down.circle", title: "Downloads")
                        }

                        if authRepository.currentUser?.isAdminUser == true {
                            Divider()
                                .background(Color.sapphoSurface)

                            NavigationLink {
                                AdminView()
                            } label: {
                                SettingsRow(icon: "wrench.and.screwdriver", title: "Admin")
                            }
                        }
                    }
                    .background(Color.sapphoSurface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)

                    // Logout Button
                    Button {
                        showLogoutConfirmation = true
                    } label: {
                        Text("Logout")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SapphoSecondaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Server Info
                    if let serverURL = authRepository.serverURL {
                        Text("Connected to: \(serverURL.host ?? serverURL.absoluteString)")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    authRepository.clear()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
        .task {
            await loadStats()
        }
    }

    private func loadStats() async {
        do {
            stats = try await api?.getProfileStats()
        } catch {
            print("Failed to load stats: \(error)")
        }
        isLoading = false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d"
        }
        return "\(hours)h"
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoPrimary)

            Text(title)
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
    }
}

// MARK: - Settings Row
struct SettingsRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.sapphoPrimary)
                .frame(width: 24)

            Text(title)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextHigh)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Placeholder Views
struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sapphoBackground)
            .navigationTitle("Settings")
    }
}

struct DownloadsView: View {
    var body: some View {
        Text("Downloads")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sapphoBackground)
            .navigationTitle("Downloads")
    }
}

struct AdminView: View {
    var body: some View {
        Text("Admin")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sapphoBackground)
            .navigationTitle("Admin")
    }
}

#Preview {
    ProfileView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
