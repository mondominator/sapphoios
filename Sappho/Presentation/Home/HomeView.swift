import SwiftUI

struct HomeView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer

    @State private var continueListening: [Audiobook] = []
    @State private var recentlyAdded: [Audiobook] = []
    @State private var listenAgain: [Audiobook] = []
    @State private var upNext: [Audiobook] = []

    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
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
        } catch {
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
        .navigationDestination(for: Audiobook.self) { audiobook in
            AudiobookDetailView(audiobook: audiobook)
        }
    }
}

// MARK: - Audiobook Card
struct AudiobookCard: View {
    @Environment(\.sapphoAPI) private var api
    let audiobook: Audiobook

    private let cardWidth: CGFloat = 140
    private let coverHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image
            AsyncImage(url: api?.coverURL(for: audiobook.id)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    coverPlaceholder
                case .empty:
                    coverPlaceholder
                        .overlay(ProgressView())
                @unknown default:
                    coverPlaceholder
                }
            }
            .frame(width: cardWidth, height: coverHeight)
            .cornerRadius(8)
            .clipped()

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

            // Progress bar (if in progress)
            if let progress = audiobook.progress, let duration = audiobook.duration, duration > 0 {
                ProgressView(value: Double(progress.position), total: Double(duration))
                    .tint(.sapphoPrimary)
            }
        }
        .frame(width: cardWidth)
    }

    private var coverPlaceholder: some View {
        Rectangle()
            .fill(Color.sapphoSurface)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.sapphoTextMuted)
            )
    }
}

#Preview {
    HomeView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
