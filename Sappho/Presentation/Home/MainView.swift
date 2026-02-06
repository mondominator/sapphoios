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
    @State private var showFullPlayer = false

    var body: some View {
        if let audiobook = audioPlayer.currentAudiobook {
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

                        Text(audiobook.author ?? "Unknown Author")
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoTextMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Play/Pause Button
                    Button {
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.sapphoTextHigh)
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.sapphoSurfaceElevated)
            }
            .buttonStyle(.plain)
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
