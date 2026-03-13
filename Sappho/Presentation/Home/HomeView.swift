import SwiftUI
import Network

struct HomeView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Binding var navigationPath: NavigationPath

    @State private var continueListening: [Audiobook] = []
    @State private var recentlyAdded: [Audiobook] = []
    @State private var listenAgain: [Audiobook] = []
    @State private var upNext: [Audiobook] = []

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isOffline = false

    private var downloadedBooks: [Audiobook] {
        DownloadManager.shared.downloadedAudiobooks()
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                            .accessibilityHint("Double tap to retry connection")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.sapphoError.opacity(0.9))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No internet connection")
                        .accessibilityAddTraits(.isStaticText)
                    }
                }

                if isLoading {
                    LoadingView(message: "Loading your library...")
                } else if let error = errorMessage, downloadedBooks.isEmpty {
                    ErrorView(message: error) {
                        Task { await loadData() }
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // Downloaded (show first when offline)
                        if isOffline && !downloadedBooks.isEmpty {
                            AudiobookSection(
                                title: "Downloaded",
                                audiobooks: downloadedBooks,
                                cardSize: 160,
                                titleSize: 20
                            )
                        }

                        // Continue Listening
                        if !continueListening.isEmpty {
                            AudiobookSection(
                                title: "Continue Listening",
                                audiobooks: continueListening,
                                cardSize: 160,
                                titleSize: 20
                            )
                        }

                        // Up Next
                        if !upNext.isEmpty {
                            AudiobookSection(
                                title: "Up Next",
                                audiobooks: upNext,
                                cardSize: 140,
                                titleSize: 16
                            )
                        }

                        // Recently Added
                        if !recentlyAdded.isEmpty {
                            AudiobookSection(
                                title: "Recently Added",
                                audiobooks: recentlyAdded,
                                cardSize: 140,
                                titleSize: 16
                            )
                        }

                        // Listen Again
                        if !listenAgain.isEmpty {
                            AudiobookSection(
                                title: "Listen Again",
                                audiobooks: listenAgain,
                                cardSize: 110,
                                titleSize: 14,
                                showCheckmark: false
                            )
                        }

                        // Downloaded (normal position when online)
                        if !isOffline && !downloadedBooks.isEmpty {
                            AudiobookSection(
                                title: "Downloaded",
                                audiobooks: downloadedBooks,
                                cardSize: 140,
                                titleSize: 16
                            )
                        }

                        // Empty state
                        if continueListening.isEmpty && recentlyAdded.isEmpty && listenAgain.isEmpty && upNext.isEmpty && downloadedBooks.isEmpty {
                            EmptyStateView(
                                icon: "books.vertical",
                                title: "No Audiobooks Yet",
                                message: "Add some audiobooks to your library to get started."
                            )
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 80)
                }
            }
            .background(Color.sapphoBackground)
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

        continueListening = (try? await api?.getInProgress(limit: 10)) ?? []
        recentlyAdded = (try? await api?.getRecentlyAdded(limit: 10)) ?? []
        listenAgain = (try? await api?.getFinished(limit: 10)) ?? []
        upNext = (try? await api?.getUpNext(limit: 10)) ?? []

        if !continueListening.isEmpty || !recentlyAdded.isEmpty || !listenAgain.isEmpty || !upNext.isEmpty {
            errorMessage = nil
            isOffline = false
        }

        isLoading = false
    }
}

// MARK: - Audiobook Section
struct AudiobookSection: View {
    let title: String
    let audiobooks: [Audiobook]
    var cardSize: CGFloat = 140
    var titleSize: CGFloat = 16
    var showCheckmark: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundColor(.sapphoTextHigh)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(audiobooks) { audiobook in
                        NavigationLink(value: audiobook) {
                            AudiobookCard(
                                audiobook: audiobook,
                                cardSize: cardSize,
                                showCheckmark: showCheckmark
                            )
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
    var cardSize: CGFloat = 140
    var showCheckmark: Bool = true

    private var progressPercent: Double {
        guard let progress = audiobook.progress,
              let duration = audiobook.duration,
              duration > 0 else { return 0 }
        return Double(progress.position) / Double(duration)
    }

    var body: some View {
        ZStack {
            // Cover image
            CoverImage(audiobookId: audiobook.id, cornerRadius: 0)
                .frame(width: cardSize, height: cardSize)

            // Overlay container
            VStack(spacing: 0) {
                // Top row: checkmark (top-start) and ribbon (top-end)
                HStack(alignment: .top, spacing: 0) {
                    // Completed checkmark (top-left)
                    if showCheckmark && audiobook.progress?.completed == 1 {
                        ZStack {
                            Circle()
                                .fill(Color.sapphoSuccess)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(6)
                        .accessibilityLabel("Completed")
                    }

                    Spacer()

                    // Reading list ribbon (top-right) - triangle shape
                    if audiobook.isQueued == true {
                        BookmarkRibbon()
                            .fill(Color.sapphoPrimary)
                            .frame(width: 28, height: 28)
                            .accessibilityLabel("In reading list")
                    }
                }

                Spacer()

                // Progress bar at bottom
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
                    .frame(height: 6)
                    .accessibilityLabel("\(Int(progressPercent * 100)) percent complete")
                }
            }
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(audiobook.title), by \(audiobook.author ?? "Unknown Author")\(audiobook.progress?.completed == 1 ? ", Completed" : progressPercent > 0 ? ", \(Int(progressPercent * 100)) percent complete" : "")\(audiobook.isQueued == true ? ", In reading list" : "")")
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Bookmark Ribbon Shape
struct BookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Triangle in top-right corner
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HomeView(navigationPath: .constant(NavigationPath()))
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
