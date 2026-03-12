import SwiftUI

// MARK: - Tab Enum
enum Tab {
    case home
    case library
    case search
}

struct MainView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.sapphoAPI) private var api

    @State private var selectedTab: Tab = .home
    @State private var showFullPlayer = false
    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    @State private var showDownloads = false
    @State private var showAdmin = false
    @State private var serverVersion: String?
    @State private var avatarURL: URL?
    @State private var homeNavigationPath = NavigationPath()

    private var downloadManager: DownloadManager { DownloadManager.shared }

    private var downloadCount: Int {
        downloadManager.downloads.values.filter {
            if case .downloaded = $0 { return true }
            return false
        }.count
    }

    private var userInitial: String {
        let name = authRepository.currentUser?.username
            ?? authRepository.currentLoginUser?.username
            ?? "?"
        return String(name.prefix(1)).uppercased()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            topBar

            // Content
            Group {
                if showProfile {
                    ProfileView()
                } else {
                    switch selectedTab {
                    case .home:
                        HomeView(navigationPath: $homeNavigationPath)
                    case .library:
                        LibraryView()
                    case .search:
                        SearchView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.sapphoBackground)
        .safeAreaInset(edge: .bottom) {
            if audioPlayer.currentAudiobook != nil {
                MiniPlayerView(showFullPlayer: $showFullPlayer)
            }
        }
        .sheet(isPresented: $showFullPlayer) {
            PlayerView()
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.sapphoBackground)
        }
        .sheet(isPresented: $showDownloads) {
            NavigationStack {
                DownloadsView()
            }
        }
        .sheet(isPresented: $showAdmin) {
            NavigationStack {
                AdminView()
            }
        }
        .alert("Logout", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Logout", role: .destructive) {
                authRepository.clear()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .task {
            await loadServerVersion()
            avatarURL = api?.avatarURL()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Logo - tappable to go Home
            Button {
                showProfile = false
                if selectedTab == .home {
                    homeNavigationPath = NavigationPath()
                } else {
                    selectedTab = .home
                }
            } label: {
                Image("SapphoLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            // Navigation Icons
            HStack(spacing: 4) {
                tabButton(tab: .home, icon: "house.fill")
                tabButton(tab: .library, icon: "books.vertical.fill")
                tabButton(tab: .search, icon: "magnifyingglass")
            }

            Spacer()

            // Avatar with dropdown menu
            avatarMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.sapphoSurface)
    }

    private func tabButton(tab: Tab, icon: String) -> some View {
        Button {
            showProfile = false
            if selectedTab == tab && tab == .home {
                homeNavigationPath = NavigationPath()
            } else {
                selectedTab = tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.sapphoTextMuted)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Avatar Menu

    private var avatarMenu: some View {
        Menu {
            // Profile
            Button {
                showProfile = true
            } label: {
                Label("Profile", systemImage: "person.fill")
            }

            // Downloads
            Button {
                showDownloads = true
            } label: {
                Label(
                    downloadCount > 0 ? "Downloads (\(downloadCount))" : "Downloads",
                    systemImage: "arrow.down.circle"
                )
            }

            // Admin (if admin)
            if authRepository.isAdmin {
                Button {
                    showAdmin = true
                } label: {
                    Label("Admin", systemImage: "gearshape.fill")
                }
            }

            Divider()

            // Logout
            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Divider()

            // Version info (non-interactive labels)
            Text("App v\(appVersion)")
            if let serverVersion {
                Text("Server v\(serverVersion)")
            }
        } label: {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    default:
                        avatarInitialView
                    }
                }
                .frame(width: 40, height: 40)
            } else {
                avatarInitialView
            }
        }
    }

    private var avatarInitialView: some View {
        ZStack {
            Circle()
                .fill(Color.sapphoPrimary)
                .frame(width: 40, height: 40)
            Text(userInitial)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Helpers

    private func loadServerVersion() async {
        do {
            let health = try await api?.getHealth()
            serverVersion = health?.version
        } catch {
            // Silently fail - version info is non-critical
        }
    }
}

// MARK: - Mini Player
struct MiniPlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Binding var showFullPlayer: Bool

    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    private var progressPercent: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        if isSeeking { return seekPosition }
        return audioPlayer.position / audioPlayer.duration
    }

    private var playButtonColor: Color {
        audioPlayer.isPlaying
            ? Color(red: 0.204, green: 0.827, blue: 0.600)  // #34D399 green
            : Color(red: 0.376, green: 0.647, blue: 0.980)  // #60A5FA blue
    }

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            VStack(spacing: 0) {
                // Interactive progress bar at top
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track (thin, centered vertically)
                        Rectangle()
                            .fill(Color(red: 0.216, green: 0.255, blue: 0.318)) // #374151
                            .frame(height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // Progress fill
                        Rectangle()
                            .fill(Color(red: 0.376, green: 0.647, blue: 0.980)) // #60A5FA
                            .frame(width: geometry.size.width * max(0, min(1, progressPercent)), height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // Thumb circle
                        if progressPercent > 0 {
                            Circle()
                                .fill(Color(red: 0.376, green: 0.647, blue: 0.980))
                                .frame(width: 12, height: 12)
                                .offset(x: geometry.size.width * max(0, min(1, progressPercent)) - 6)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isSeeking = true
                                let percent = max(0, min(1, value.location.x / geometry.size.width))
                                seekPosition = percent
                            }
                            .onEnded { value in
                                let percent = max(0, min(1, value.location.x / geometry.size.width))
                                let targetTime = percent * audioPlayer.duration
                                Task {
                                    await audioPlayer.seek(to: targetTime)
                                }
                                isSeeking = false
                            }
                    )
                }
                .frame(height: 20)
                .padding(.horizontal, 8)

                // Main content
                HStack(spacing: 10) {
                    // Cover Image
                    CoverImage(audiobookId: audiobook.id, cornerRadius: 6)
                        .frame(width: 48, height: 48)

                    // Title, Author, Time
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audiobook.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(audiobook.author ?? "Unknown Author")
                                .lineLimit(1)

                            if audioPlayer.isBuffering {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.sapphoTextMuted)

                        // Time display
                        MiniPlayerTimeDisplay(
                            position: audioPlayer.position,
                            duration: audioPlayer.duration,
                            isPlaying: audioPlayer.isPlaying
                        )
                    }

                    Spacer()

                    // Skip backward (Replay 10)
                    Button {
                        audioPlayer.skipBackward(seconds: 10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 20))
                            .foregroundColor(.sapphoTextMuted)
                    }
                    .frame(width: 40, height: 40)

                    // Play/Pause Button
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(playButtonColor)
                                .frame(width: 44, height: 44)
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }

                    // Skip forward (Forward 10)
                    Button {
                        audioPlayer.skipForward(seconds: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 20))
                            .foregroundColor(.sapphoTextMuted)
                    }
                    .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .background(Color(red: 0.118, green: 0.161, blue: 0.231)) // #1E293B
            .contentShape(Rectangle())
            .onTapGesture {
                showFullPlayer = true
            }
        }
    }
}

// MARK: - Mini Player Time Display
struct MiniPlayerTimeDisplay: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool

    @State private var pulsePhase = false

    private var timeText: String {
        "\(formatTime(position)) / \(formatTime(duration))"
    }

    private var textColor: Color {
        if isPlaying {
            return pulsePhase
                ? Color(red: 0.376, green: 0.647, blue: 0.980)  // #60A5FA
                : Color(red: 0.576, green: 0.773, blue: 0.988)  // #93C5FD
        }
        return .sapphoTextMuted
    }

    var body: some View {
        Text(timeText)
            .font(.system(size: 10))
            .foregroundColor(textColor)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsePhase)
            .onAppear {
                pulsePhase = true
            }
            .onChange(of: isPlaying) { _, playing in
                pulsePhase = playing
            }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    MainView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
