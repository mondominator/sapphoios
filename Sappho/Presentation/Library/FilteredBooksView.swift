import SwiftUI

enum FilterType {
    case series(String)
    case author(String)
    case genre(String)
    case collection(Int)
}

struct FilteredBooksView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var audiobooks: [Audiobook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    let title: String
    let filterType: FilterType

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadData() }
                }
            } else if audiobooks.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Books",
                    message: "No audiobooks found in this category."
                )
            } else {
                ScrollView {
                    // Header stats
                    if case .series = filterType {
                        SeriesHeaderView(audiobooks: audiobooks)
                    }

                    LazyVStack(spacing: 12) {
                        ForEach(audiobooks) { audiobook in
                            NavigationLink {
                                AudiobookDetailView(audiobook: audiobook)
                            } label: {
                                BookListItem(audiobook: audiobook)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                }
            }
        }
        .background(Color.sapphoBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            switch filterType {
            case .series(let seriesName):
                audiobooks = try await api?.getAudiobooksBySeries(seriesName) ?? []
                // Sort by series position
                audiobooks.sort { ($0.seriesPosition ?? 0) < ($1.seriesPosition ?? 0) }
            case .author(let authorName):
                audiobooks = try await api?.getAudiobooksByAuthor(authorName) ?? []
                // Sort by title
                audiobooks.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
            case .genre(let genreName):
                audiobooks = try await api?.getAudiobooksByGenre(genreName) ?? []
                // Sort by title
                audiobooks.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
            case .collection(let collectionId):
                let collection = try await api?.getCollection(id: collectionId)
                audiobooks = collection?.books ?? []
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct SeriesHeaderView: View {
    let audiobooks: [Audiobook]

    private var totalDuration: Int {
        audiobooks.compactMap { $0.duration }.reduce(0, +)
    }

    private var completedCount: Int {
        audiobooks.filter { $0.progress?.completed == 1 }.count
    }

    private var inProgressCount: Int {
        audiobooks.filter { book in
            guard let progress = book.progress else { return false }
            return progress.completed != 1 && progress.position > 0
        }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                StatItem(
                    icon: "book.closed.fill",
                    value: "\(audiobooks.count)",
                    label: "Books",
                    color: .sapphoPrimary
                )

                StatItem(
                    icon: "clock",
                    value: formatDuration(totalDuration),
                    label: "Total",
                    color: .sapphoPrimary
                )

                if completedCount > 0 {
                    StatItem(
                        icon: "checkmark.circle.fill",
                        value: "\(completedCount)",
                        label: "Completed",
                        color: .sapphoSuccess
                    )
                }

                if inProgressCount > 0 {
                    StatItem(
                        icon: "play.circle.fill",
                        value: "\(inProgressCount)",
                        label: "In Progress",
                        color: .sapphoWarning
                    )
                }
            }
        }
        .padding(16)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(value)
                .font(.sapphoSubheadline)
                .foregroundColor(.sapphoTextHigh)

            Text(label)
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)
        }
    }
}

struct BookListItem: View {
    @Environment(\.sapphoAPI) private var api
    let audiobook: Audiobook

    private var progressPercent: Double? {
        guard let progress = audiobook.progress,
              let duration = audiobook.duration,
              duration > 0 else { return nil }
        return Double(progress.position) / Double(duration)
    }

    private var isCompleted: Bool {
        audiobook.progress?.completed == 1
    }

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            CoverImage(audiobookId: audiobook.id)
                .frame(width: 70, height: 100)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sapphoSurface.opacity(0.5), lineWidth: 1)
                )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Series position badge
                if let position = audiobook.seriesPosition {
                    Text("Book \(formatSeriesPosition(position))")
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoPrimary)
                }

                Text(audiobook.title)
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(2)

                if let narrator = audiobook.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                        .lineLimit(1)
                }

                Spacer().frame(height: 4)

                // Duration and progress
                HStack(spacing: 12) {
                    if let duration = audiobook.duration {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(formatDuration(duration))
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoTextMuted)
                    }

                    if isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Completed")
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoSuccess)
                    } else if let percent = progressPercent, percent > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 10))
                            Text("\(Int(percent * 100))%")
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoWarning)
                    }

                    // User rating
                    if let rating = audiobook.userRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.0f", rating))
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoWarning)
                    }
                }

                // Progress bar
                if let percent = progressPercent, !isCompleted {
                    ProgressView(value: percent)
                        .tint(.sapphoPrimary)
                        .scaleEffect(y: 0.5)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatSeriesPosition(_ position: Float) -> String {
        if position == floor(position) {
            return String(format: "%.0f", position)
        }
        return String(format: "%.1f", position)
    }
}

#Preview {
    NavigationStack {
        FilteredBooksView(
            title: "Test Series",
            filterType: .series("Test Series")
        )
    }
    .environment(AuthRepository())
}
