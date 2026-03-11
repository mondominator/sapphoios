import SwiftUI

struct MainView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical.fill")
                    }
                    .tag(1)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2)

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(3)
            }
            .tint(.sapphoPrimary)

            // Mini Player (shown when audiobook is playing)
            if audioPlayer.currentAudiobook != nil {
                MiniPlayerView()
                    .padding(.bottom, 49) // Tab bar height
            }
        }
    }
}

// MARK: - Mini Player
struct MiniPlayerView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.sapphoAPI) private var api
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 30
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 15
    @State private var showFullPlayer = false

    private var progressPercent: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        return audioPlayer.position / audioPlayer.duration
    }

    private var skipBackwardIcon: String {
        let validSeconds = [5, 10, 15, 30, 45, 60, 75, 90]
        let seconds = validSeconds.contains(skipBackwardSeconds) ? skipBackwardSeconds : 15
        return "gobackward.\(seconds)"
    }

    private var skipForwardIcon: String {
        let validSeconds = [5, 10, 15, 30, 45, 60, 75, 90]
        let seconds = validSeconds.contains(skipForwardSeconds) ? skipForwardSeconds : 30
        return "goforward.\(seconds)"
    }

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
            VStack(spacing: 0) {
                // Progress bar at top
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.sapphoPrimary)
                        .frame(width: geometry.size.width * progressPercent)
                }
                .frame(height: 3)
                .background(Color.sapphoSurface)

                // Main content
                Button {
                    showFullPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        // Cover Image
                        AsyncImage(url: api?.coverURL(for: audiobook.id)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.sapphoSurface)
                                .overlay(
                                    Image(systemName: "book.closed.fill")
                                        .foregroundColor(.sapphoTextMuted)
                                )
                        }
                        .frame(width: 48, height: 48)
                        .cornerRadius(6)

                        // Title and Author
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audiobook.title)
                                .font(.sapphoSubheadline)
                                .foregroundColor(.sapphoTextHigh)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Text(audiobook.author ?? "Unknown Author")
                                    .lineLimit(1)

                                if audioPlayer.isBuffering {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                            }
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoTextMuted)
                        }

                        Spacer()

                        // Skip backward
                        Button {
                            audioPlayer.skipBackward(seconds: TimeInterval(skipBackwardSeconds))
                        } label: {
                            Image(systemName: skipBackwardIcon)
                                .font(.system(size: 18))
                                .foregroundColor(.sapphoTextMuted)
                        }
                        .padding(.horizontal, 4)

                        // Play/Pause Button
                        Button {
                            audioPlayer.togglePlayPause()
                        } label: {
                            Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.sapphoTextHigh)
                        }
                        .padding(.horizontal, 4)

                        // Skip forward
                        Button {
                            audioPlayer.skipForward(seconds: TimeInterval(skipForwardSeconds))
                        } label: {
                            Image(systemName: skipForwardIcon)
                                .font(.system(size: 18))
                                .foregroundColor(.sapphoTextMuted)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .background(Color.sapphoSurfaceElevated)
            .fullScreenCover(isPresented: $showFullPlayer) {
                PlayerView()
            }
        }
    }
}

#Preview {
    MainView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
