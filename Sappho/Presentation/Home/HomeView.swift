import SwiftUI
import Network

struct HomeView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer

    @State private var continueListening: [Audiobook] = []
    @State private var recentlyAdded: [Audiobook] = []
    @State private var listenAgain: [Audiobook] = []
    @State private var upNext: [Audiobook] = []

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isOffline = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Offline banner
                    if isOffline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 14))
                            Text("No internet connection")
                                .font(.sapphoCaption)
                            Spacer()
                            Button("Retry") {
                                Task { await loadData() }
                            }
                            .font(.sapphoCaption)
                            .foregroundColor(.white)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.sapphoError.opacity(0.9))
                    }
                }

                if isLoading {
                    LoadingView(message: "Loading your library...")
                } else if let error = errorMessage {
                    ErrorView(message: error) {
                        Task { await loadData() }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        // Continue Listening
                        if !continueListening.isEmpty {
                            AudiobookSection(
                                title: "Continue Listening",
                                audiobooks: continueListening
                            )
                        }

                        // Up Next
                        if !upNext.isEmpty {
                            AudiobookSection(
                                title: "Up Next",
                                audiobooks: upNext
                            )
                        }

                        // Recently Added
                        if !recentlyAdded.isEmpty {
                            AudiobookSection(
                                title: "Recently Added",
                                audiobooks: recentlyAdded
                            )
                        }

                        // Listen Again
                        if !listenAgain.isEmpty {
                            AudiobookSection(
                                title: "Listen Again",
                                audiobooks: listenAgain
                            )
                        }

                        // Empty state
                        if continueListening.isEmpty && recentlyAdded.isEmpty && listenAgain.isEmpty && upNext.isEmpty {
                            EmptyStateView(
                                icon: "books.vertical",
                                title: "No Audiobooks Yet",
                                message: "Add some audiobooks to your library to get started."
                            )
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable {
                await loadData()
            }
            .navigationDestination(for: Audiobook.self) { audiobook in
                AudiobookDetailView(audiobook: audiobook)
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = errorMessage != nil || continueListening.isEmpty

        do {
            async let inProgress = api?.getInProgress(limit: 10)
            async let recent = api?.getRecentlyAdded(limit: 10)
            async let finished = api?.getFinished(limit: 10)
            async let next = api?.getUpNext(limit: 10)

            continueListening = try await inProgress ?? []
            recentlyAdded = try await recent ?? []
            listenAgain = try await finished ?? []
            upNext = try await next ?? []

            errorMessage = nil
            isOffline = false
        } catch {
            if case APIError.networkError = error {
                isOffline = true
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Audiobook Section
struct AudiobookSection: View {
    let title: String
    let audiobooks: [Audiobook]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoTextHigh)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(audiobooks) { audiobook in
                        NavigationLink(value: audiobook) {
                            AudiobookCard(audiobook: audiobook)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Audiobook Card
struct AudiobookCard: View {
    let audiobook: Audiobook

    private let cardWidth: CGFloat = 140
    private let coverHeight: CGFloat = 140  // Square covers like audiobook art

    private var downloadManager: DownloadManager { DownloadManager.shared }
    private var isDownloaded: Bool { downloadManager.isDownloaded(audiobook.id) }

    private var progressPercent: Double {
        guard let progress = audiobook.progress,
              let duration = audiobook.duration,
              duration > 0 else { return 0 }
        return Double(progress.position) / Double(duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image with overlays
            ZStack {
                // Cover image
                CoverImage(audiobookId: audiobook.id, cornerRadius: 0)
                    .frame(width: cardWidth, height: coverHeight)

                // Overlay container
                VStack(spacing: 0) {
                    // Top row: badges
                    HStack(alignment: .top) {
                        // Reading list ribbon (top-left)
                        if audiobook.isQueued == true {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.sapphoPrimary)
                        }

                        Spacer()

                        // Status badges (top-right)
                        VStack(alignment: .trailing, spacing: 4) {
                            if audiobook.isFavorite == true {
                                statusBadge(icon: "heart.fill", color: .sapphoError)
                            }
                            if isDownloaded {
                                statusBadge(icon: "arrow.down.circle.fill", color: .sapphoSuccess)
                            }
                        }
                        .padding(6)
                    }

                    Spacer()

                    // Bottom row: rating badge + progress bar
                    VStack(spacing: 0) {
                        HStack {
                            // Completed checkmark (bottom-left)
                            if audiobook.progress?.completed == 1 {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.sapphoSuccess)
                                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                    .padding(6)
                            }

                            Spacer()

                            // Rating badge (bottom-right)
                            if let rating = audiobook.userRating ?? audiobook.averageRating, rating > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.sapphoWarning)
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(6)
                            }
                        }

                        // Progress bar
                        if progressPercent > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.5))
                                    Rectangle()
                                        .fill(audiobook.progress?.completed == 1 ? Color.sapphoSuccess : Color.sapphoPrimary)
                                        .frame(width: geo.size.width * progressPercent)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
            .frame(width: cardWidth, height: coverHeight)
            .cornerRadius(8)

            // Title
            Text(audiobook.title)
                .font(.sapphoCaption)
                .foregroundColor(.sapphoTextHigh)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Author
            if let author = audiobook.author {
                Text(author)
                    .font(.sapphoSmall)
                    .foregroundColor(.sapphoTextMuted)
                    .lineLimit(1)
            }
        }
        .frame(width: cardWidth)
    }

    private func statusBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(4)
            .background(color)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    HomeView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
