import SwiftUI

struct SeriesListView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var series: [SeriesInfo] = []
    @State private var allBooks: [Audiobook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadData() }
                }
            } else if series.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Series",
                    message: "Your library doesn't have any series yet."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(series) { seriesItem in
                            let seriesBooks = allBooks.filter { $0.series == seriesItem.series }
                                .sorted { ($0.seriesPosition ?? 0) < ($1.seriesPosition ?? 0) }

                            NavigationLink {
                                FilteredBooksView(
                                    title: seriesItem.series,
                                    filterType: .series(seriesItem.series)
                                )
                            } label: {
                                SeriesCard(
                                    seriesInfo: seriesItem,
                                    books: seriesBooks
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100) // Space for mini player
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .background(Color.sapphoBackground)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let seriesData = api?.getSeries()
            async let booksData = api?.getAudiobooks(limit: 10000)

            series = try await seriesData ?? []
            allBooks = try await booksData ?? []

            // Sort series by book count (descending)
            series.sort { $0.bookCount > $1.bookCount }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct SeriesCard: View {
    @Environment(\.sapphoAPI) private var api
    let seriesInfo: SeriesInfo
    let books: [Audiobook]

    private var totalDuration: Int {
        books.compactMap { $0.duration }.reduce(0, +)
    }

    private var completedCount: Int {
        books.filter { $0.progress?.completed == 1 }.count
    }

    private var authors: [String] {
        Array(Set(books.compactMap { $0.author })).prefix(2).map { $0 }
    }

    private var gradientColors: [Color] {
        // Generate gradient based on series name hash
        let hash = abs(seriesInfo.series.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.6, brightness: 0.3),
            Color(hue: hue2, saturation: 0.5, brightness: 0.25)
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            // Cover (first book in series)
            if let firstBook = books.first {
                CoverImage(audiobookId: firstBook.id, cornerRadius: 8, contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.sapphoSurface)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "books.vertical.fill")
                            .foregroundColor(.sapphoTextMuted)
                    )
            }

            // Series info
            VStack(alignment: .leading, spacing: 4) {
                Text(seriesInfo.series)
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(2)

                if !authors.isEmpty {
                    Text(authors.joined(separator: ", "))
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                        .lineLimit(1)
                }

                Spacer().frame(height: 4)

                // Stats row
                HStack(spacing: 12) {
                    // Book count
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed.fill")
                            .font(.sapphoIconMini)
                            .foregroundColor(.sapphoPrimary)
                        Text("\(seriesInfo.bookCount)")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }

                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.sapphoIconMini)
                            .foregroundColor(.sapphoPrimary)
                        Text("\(totalDuration / 3600)h")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }

                    // Completed
                    if completedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.sapphoIconMini)
                                .foregroundColor(.sapphoSuccess)
                            Text("\(completedCount)/\(seriesInfo.bookCount)")
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoSuccess)
                        }
                    }

                    // Rating
                    if let avgRating = seriesInfo.averageRating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.sapphoIconMini)
                                .foregroundColor(.sapphoWarning)
                            Text(String(format: "%.1f", avgRating))
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoTextMuted)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.sapphoDetail)
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(16)
        .background(
            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
        )
        .background(Color.sapphoSurface)
        .cornerRadius(16)
    }
}


#Preview {
    NavigationStack {
        SeriesListView()
    }
    .environment(AuthRepository())
}
