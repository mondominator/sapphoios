import SwiftUI

struct AuthorsListView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var authors: [AuthorInfo] = []
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
            } else if authors.isEmpty {
                EmptyStateView(
                    icon: "person.2",
                    title: "No Authors",
                    message: "Your library doesn't have any authors yet."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(authors) { authorInfo in
                            let authorBooks = allBooks.filter { $0.author == authorInfo.author }

                            NavigationLink {
                                FilteredBooksView(
                                    title: authorInfo.author,
                                    filterType: .author(authorInfo.author)
                                )
                            } label: {
                                AuthorCard(
                                    authorInfo: authorInfo,
                                    books: authorBooks
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100)
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
            async let authorsData = api?.getAuthors()
            async let booksData = api?.getAudiobooks()

            authors = try await authorsData ?? []
            allBooks = try await booksData ?? []

            // Sort authors by book count (descending)
            authors.sort { $0.bookCount > $1.bookCount }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct AuthorCard: View {
    @Environment(\.sapphoAPI) private var api
    let authorInfo: AuthorInfo
    let books: [Audiobook]

    private var totalDuration: Int {
        books.compactMap { $0.duration }.reduce(0, +)
    }

    private var completedCount: Int {
        books.filter { $0.progress?.completed == 1 }.count
    }

    private var seriesNames: [String] {
        Array(Set(books.compactMap { $0.series })).prefix(2).map { $0 }
    }

    private var gradientColors: [Color] {
        let hash = abs(authorInfo.author.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = Double((hash / 360) % 360) / 360.0
        return [
            Color(hue: hue1, saturation: 0.5, brightness: 0.35),
            Color(hue: hue2, saturation: 0.4, brightness: 0.3)
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            // Stacked covers
            ZStack {
                ForEach(Array(books.prefix(3).reversed().enumerated()), id: \.offset) { index, book in
                    let offset = CGFloat(2 - index) * 8
                    CoverImage(audiobookId: book.id)
                        .frame(width: 60, height: 80)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.sapphoSurface, lineWidth: 1)
                        )
                        .offset(x: offset, y: offset)
                }
            }
            .frame(width: 80, height: 100)

            // Author info
            VStack(alignment: .leading, spacing: 4) {
                Text(authorInfo.author)
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(2)

                if !seriesNames.isEmpty {
                    Text(seriesNames.joined(separator: ", "))
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
                            .font(.system(size: 12))
                            .foregroundColor(.sapphoPrimary)
                        Text("\(authorInfo.bookCount)")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }

                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.sapphoPrimary)
                        Text("\(totalDuration / 3600)h")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }

                    // Completed
                    if completedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.sapphoSuccess)
                            Text("\(completedCount)/\(authorInfo.bookCount)")
                                .font(.sapphoSmall)
                                .foregroundColor(.sapphoSuccess)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
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
        AuthorsListView()
    }
    .environment(AuthRepository())
}
