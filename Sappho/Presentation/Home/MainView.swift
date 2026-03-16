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
    @Environment(\.scenePhase) private var scenePhase

    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    @State private var showDownloads = false
    @State private var showAdmin = false
    @State private var showNotificationPanel = false
    @State private var serverVersion: String?
    @State private var avatarLoader = ImageLoader()
    @State private var homeNavigationPath = NavigationPath()
    @State private var libraryNavigationPath = NavigationPath()
    @State private var unreadCount: Int = 0

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
        .sheet(isPresented: $showNotificationPanel) {
            NotificationPanel {
                Task { await refreshUnreadCount() }
            }
        }
        .task {
            await loadServerVersion()
            avatarLoader.load(url: api?.avatarURL(), headers: api?.authHeaders ?? [:])
        }
        .task {
            // Poll unread notification count every 2 minutes
            while !Task.isCancelled {
                await refreshUnreadCount()
                try? await Task.sleep(for: .seconds(120))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshUnreadCount() }
            }
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

            // Notification bell
            notificationBell

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

    // MARK: - Notification Bell

    private var notificationBell: some View {
        Button {
            showNotificationPanel = true
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 20))
                .foregroundColor(.sapphoTextMuted)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 8, y: -4)
                    }
                }
        }
        .accessibilityLabel("Notifications")
        .accessibilityHint(unreadCount > 0 ? "\(unreadCount) unread notifications" : "No unread notifications")
    }

    // MARK: - Helpers

    private func refreshUnreadCount() async {
        if let count = try? await api?.getUnreadNotificationCount() {
            await MainActor.run {
                unreadCount = count.count
            }
        }
    }

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
    @State private var coverPulsing = false
    @State private var gradientPhase: CGFloat = 0

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
                // Animated gradient progress bar
                GeometryReader { geometry in
                    let progressWidth = geometry.size.width * max(0, min(1, progressPercent))
                    ZStack(alignment: .leading) {
                        // Track
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // Animated gradient fill
                        Rectangle()
                            .fill(
                                audioPlayer.isPlaying
                                    ? LinearGradient(
                                        colors: [
                                            Color.sapphoPrimaryLight,
                                            Color.sapphoPlayingGreen,
                                            Color.sapphoPrimaryLight
                                        ],
                                        startPoint: UnitPoint(x: gradientPhase - 0.5, y: 0.5),
                                        endPoint: UnitPoint(x: gradientPhase + 0.5, y: 0.5)
                                    )
                                    : LinearGradient(
                                        colors: [Color.sapphoPrimaryLight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .frame(width: progressWidth, height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        // Glowing thumb
                        if progressPercent > 0 {
                            Circle()
                                .fill(audioPlayer.isPlaying ? Color.sapphoPlayingGreen : Color.sapphoPrimaryLight)
                                .frame(width: 12, height: 12)
                                .shadow(color: (audioPlayer.isPlaying ? Color.sapphoPlayingGreen : Color.sapphoPrimaryLight).opacity(0.6), radius: audioPlayer.isPlaying ? 6 : 2)
                                .offset(x: progressWidth - 6)
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
                HStack(spacing: 10) {
                    // Cover art (tappable to open full player)
                    CoverImage(audiobookId: audiobook.id, cornerRadius: 8)
                        .frame(width: 56, height: 56)
                        .shadow(color: (audioPlayer.isPlaying ? Color.sapphoPlayingGreen : Color.sapphoPrimaryLight).opacity(0.4), radius: 8)
                        .scaleEffect(audioPlayer.isPlaying && coverPulsing ? 1.04 : 1.0)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                audioPlayer.showFullPlayer = true
                            }
                        }

                    // Title + Author + Chapter (tappable to open full player)
                    VStack(alignment: .leading, spacing: 2) {
                        // Marquee title when playing, static when paused
                        if audioPlayer.isPlaying {
                            MarqueeText(text: audiobook.title, font: .system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Text(audiobook.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }

                        Text(audiobook.author ?? "Unknown Author")
                            .font(.system(size: 11))
                            .foregroundColor(.sapphoTextMuted)
                            .lineLimit(1)

                        // Chapter name (if available)
                        if let chapter = audioPlayer.currentChapter, let chapterTitle = chapter.title {
                            Text(chapterTitle)
                                .font(.system(size: 10))
                                .foregroundColor(Color.sapphoPrimaryLight.opacity(0.8))
                                .lineLimit(1)
                        } else {
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

                    Spacer(minLength: 4)

                    // Waveform visualizer (when playing)
                    if audioPlayer.isPlaying {
                        MiniPlayerWaveAnimation()
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Skip backward
                    Button {
                        audioPlayer.skipBackward(seconds: 10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 18))
                            .foregroundColor(.sapphoTextMuted)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("Skip back 10 seconds")

                    // Play/Pause
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(playButtonColor)
                                .frame(width: 52, height: 52)
                                .shadow(color: playButtonColor.opacity(0.4), radius: audioPlayer.isPlaying ? 8 : 0)
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                    .accessibilityHint(audioPlayer.isPlaying ? "Double tap to pause playback" : "Double tap to resume playback")

                    // Skip forward
                    Button {
                        audioPlayer.skipForward(seconds: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 18))
                            .foregroundColor(.sapphoTextMuted)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("Skip forward 10 seconds")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.sapphoSurfaceElevated)
            .animation(.easeInOut(duration: 0.3), value: audioPlayer.isPlaying)
            .onChange(of: audioPlayer.isPlaying) { _, playing in
                if playing {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        coverPulsing = true
                    }
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                        gradientPhase = 1.5
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        coverPulsing = false
                        gradientPhase = 0
                    }
                }
            }
            .onAppear {
                if audioPlayer.isPlaying {
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        coverPulsing = true
                    }
                    withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                        gradientPhase = 1.5
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        // Swipe up to open full player
                        if value.translation.height < -50 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                audioPlayer.showFullPlayer = true
                            }
                        }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(audiobook.title) by \(audiobook.author ?? "Unknown Author")")
            .accessibilityHint("Swipe up or double tap to open full player")
        }
    }
}

// MARK: - Marquee Text
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var needsScroll: Bool { textWidth > containerWidth }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            if needsScroll {
                HStack(spacing: 40) {
                    Text(text).font(font).fixedSize()
                    Text(text).font(font).fixedSize()
                }
                .offset(x: offset)
                .onAppear {
                    containerWidth = w
                    startScrolling()
                }
                .onChange(of: text) { _, _ in
                    offset = 0
                    measureText(in: w)
                    startScrolling()
                }
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
            }
        }
        .frame(height: 18)
        .clipped()
        .background(
            Text(text).font(font).fixedSize()
                .hidden()
                .background(GeometryReader { textGeo in
                    Color.clear.onAppear {
                        textWidth = textGeo.size.width
                    }
                })
        )
    }

    private func measureText(in width: CGFloat) {
        containerWidth = width
    }

    private func startScrolling() {
        guard needsScroll else { return }
        let scrollDistance = textWidth + 40
        offset = 0
        withAnimation(.linear(duration: Double(scrollDistance) / 30.0).repeatForever(autoreverses: false)) {
            offset = -scrollDistance
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

// MARK: - Mini Player Wave Animation
struct MiniPlayerWaveAnimation: View {
    @State private var animating = false
    @State private var colorShift = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: colorShift
                                ? [colorSetsShifted[index].0, colorSetsShifted[index].1]
                                : [colorSets[index].0, colorSets[index].1],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: animating ? heights[index] : 3)
                    .animation(
                        .timingCurve(0.4, 0, 0.2, 1, duration: durations[index])
                            .repeatForever(autoreverses: true)
                            .delay(delays[index]),
                        value: animating
                    )
                    .animation(
                        .easeInOut(duration: colorDurations[index])
                            .repeatForever(autoreverses: true),
                        value: colorShift
                    )
            }
        }
        .frame(height: 14)
        .onAppear {
            animating = true
            colorShift = true
        }
    }

    private var heights: [CGFloat] { [8, 14, 10] }
    private var durations: [Double] { [1.2, 0.9, 1.1] }
    private var delays: [Double] { [0.0, 0.1, 0.05] }
    private var colorDurations: [Double] { [2.4, 2.0, 2.8] }
    private var colorSets: [(Color, Color)] {
        [(.sapphoPlayingGreen, .sapphoPrimaryLight),
         (.sapphoPrimaryLight, .sapphoPlayingGreen),
         (.sapphoPlayingGreen, .sapphoPrimaryLight)]
    }
    private var colorSetsShifted: [(Color, Color)] {
        [(.sapphoPrimaryLight, .sapphoPlayingGreen),
         (.sapphoPlayingGreen, .sapphoPrimaryLight),
         (.sapphoPrimaryLight, .sapphoPlayingGreen)]
    }
}

#Preview {
    MainView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
