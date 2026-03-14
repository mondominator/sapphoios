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
    // showFullPlayer is on audioPlayer (shared so detail screen can trigger it)
    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    @State private var showDownloads = false
    @State private var showAdmin = false
    @State private var serverVersion: String?
    @State private var avatarLoader = ImageLoader()
    @State private var homeNavigationPath = NavigationPath()
    @State private var libraryNavigationPath = NavigationPath()

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
                        LibraryView(navigationPath: $libraryNavigationPath)
                    case .search:
                        SearchView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.sapphoBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if audioPlayer.currentAudiobook != nil && !audioPlayer.showFullPlayer {
                MiniPlayerView(showFullPlayer: Binding(
                    get: { audioPlayer.showFullPlayer },
                    set: { newValue in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            audioPlayer.showFullPlayer = newValue
                        }
                    }
                ))
            }
        }
        .overlay {
            if audioPlayer.currentAudiobook != nil {
                PlayerView(showFullPlayer: Binding(
                    get: { audioPlayer.showFullPlayer },
                    set: { newValue in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            audioPlayer.showFullPlayer = newValue
                        }
                    }
                ))
                    .offset(y: audioPlayer.showFullPlayer ? 0 : UIScreen.main.bounds.height)
                    .zIndex(1)
            }
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
                audioPlayer.showFullPlayer = false
                audioPlayer.stop()
                authRepository.clear()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
        .task {
            await loadServerVersion()
            avatarLoader.load(url: api?.avatarURL(), headers: api?.authHeaders ?? [:])
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
            .accessibilityLabel("Sappho home")
            .accessibilityHint("Double tap to go to home screen")

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
        let tabLabel: String = switch tab {
        case .home: "Home"
        case .library: "Library"
        case .search: "Search"
        }
        return Button {
            showProfile = false
            if selectedTab == tab {
                switch tab {
                case .home: homeNavigationPath = NavigationPath()
                case .library: libraryNavigationPath = NavigationPath()
                case .search: break
                }
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
        .accessibilityLabel(tabLabel)
        .accessibilityHint(selectedTab == tab ? "Currently selected" : "Double tap to switch to \(tabLabel)")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
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
            if let image = avatarLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                avatarInitialView
            }
        }
        .accessibilityLabel("User menu")
        .accessibilityHint("Double tap to open profile and settings menu")
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
    @AppStorage("showChapterProgress") private var showChapterProgress = false
    @Binding var showFullPlayer: Bool

    @State private var isSeeking = false
    @State private var seekPosition: Double = 0

    private var progressPercent: Double {
        if isSeeking { return seekPosition }
        if showChapterProgress, let chapter = audioPlayer.currentChapter {
            let chapterDuration = chapter.duration ?? (audioPlayer.duration - chapter.startTime)
            guard chapterDuration > 0 else { return 0 }
            return max(0, min(1, (audioPlayer.position - chapter.startTime) / chapterDuration))
        }
        guard audioPlayer.duration > 0 else { return 0 }
        return audioPlayer.position / audioPlayer.duration
    }

    private var playButtonColor: Color {
        audioPlayer.isPlaying
            ? Color.sapphoPlayingGreen
            : Color.sapphoPrimaryLight
    }

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            VStack(spacing: 0) {
                // Interactive progress bar at top
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track (thin, centered vertically)
                        Rectangle()
                            .fill(Color.sapphoBorder)
                            .frame(height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // Progress fill
                        Rectangle()
                            .fill(Color.sapphoPrimaryLight)
                            .frame(width: geometry.size.width * max(0, min(1, progressPercent)), height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // Thumb circle
                        if progressPercent > 0 {
                            Circle()
                                .fill(Color.sapphoPrimaryLight)
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
                                let targetTime: Double
                                if showChapterProgress, let chapter = audioPlayer.currentChapter {
                                    let chapterDuration = chapter.duration ?? (audioPlayer.duration - chapter.startTime)
                                    targetTime = chapter.startTime + percent * chapterDuration
                                } else {
                                    targetTime = percent * audioPlayer.duration
                                }
                                Task {
                                    await audioPlayer.seek(to: targetTime)
                                }
                                isSeeking = false
                            }
                    )
                }
                .frame(height: 20)
                .padding(.horizontal, 8)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Int(progressPercent * 100)) percent")

                // Main content
                HStack(spacing: 8) {
                    // Cover + Title (tappable to open full player)
                    HStack(spacing: 8) {
                        CoverImage(audiobookId: audiobook.id, cornerRadius: 6)
                            .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(audiobook.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(audiobook.author ?? "Unknown Author")
                                .font(.system(size: 11))
                                .foregroundColor(.sapphoTextMuted)
                                .lineLimit(1)

                            MiniPlayerTimeDisplay(
                                position: audioPlayer.position,
                                duration: audioPlayer.duration,
                                isPlaying: audioPlayer.isPlaying,
                                showChapterProgress: showChapterProgress,
                                currentChapter: audioPlayer.currentChapter
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            audioPlayer.showFullPlayer = true
                        }
                    }

                    Spacer(minLength: 8)

                    // Play/Pause
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(playButtonColor)
                                .frame(width: 64, height: 64)
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                    .accessibilityHint(audioPlayer.isPlaying ? "Double tap to pause playback" : "Double tap to resume playback")

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color.sapphoSurface)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(audiobook.title) by \(audiobook.author ?? "Unknown Author")")
            .accessibilityHint("Double tap to open full player")
        }
    }
}

// MARK: - Mini Player Time Display
struct MiniPlayerTimeDisplay: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    var showChapterProgress: Bool = false
    var currentChapter: Chapter? = nil

    private var displayPosition: TimeInterval {
        if showChapterProgress, let chapter = currentChapter {
            return max(0, position - chapter.startTime)
        }
        return position
    }

    private var displayDuration: TimeInterval {
        if showChapterProgress, let chapter = currentChapter {
            return chapter.duration ?? (duration - chapter.startTime)
        }
        return duration
    }

    var body: some View {
        Text("\(formatTime(displayPosition)) / \(formatTime(displayDuration))")
            .font(.system(size: 10))
            .foregroundColor(isPlaying
                ? Color.sapphoPrimaryLight
                : .sapphoTextMuted
            )
            .contentTransition(.numericText())
    }

}

#Preview {
    MainView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
