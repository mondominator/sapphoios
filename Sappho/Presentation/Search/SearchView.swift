import SwiftUI

struct SearchView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var searchText = ""
    @State private var bookResults: [Audiobook] = []
    @State private var seriesResults: [SeriesInfo] = []
    @State private var authorResults: [AuthorInfo] = []
    @State private var isSearching = false

    private var hasResults: Bool {
        !bookResults.isEmpty || !seriesResults.isEmpty || !authorResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasResults && !searchText.isEmpty && !isSearching {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "No audiobooks, series, or authors found for \"\(searchText)\""
                    )
                } else if !hasResults && searchText.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Search",
                        message: "Search for audiobooks, series, or authors"
                    )
                } else if isSearching {
                    LoadingView(message: "Searching...")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            // Books Section
                            if !bookResults.isEmpty {
                                SearchSection(title: "Books", count: bookResults.count) {
                                    ForEach(bookResults.prefix(5)) { audiobook in
                                        NavigationLink(value: audiobook) {
                                            BookSearchResult(audiobook: audiobook)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if bookResults.count > 5 {
                                        NavigationLink {
                                            AllBooksSearchResults(books: bookResults, searchText: searchText)
                                        } label: {
                                            Text("See all \(bookResults.count) books")
                                                .font(.sapphoCaption)
                                                .foregroundColor(.sapphoPrimary)
                                                .padding(.top, 8)
                                        }
                                    }
                                }
                            }

                            // Series Section
                            if !seriesResults.isEmpty {
                                SearchSection(title: "Series", count: seriesResults.count) {
                                    ForEach(seriesResults.prefix(5)) { series in
                                        NavigationLink {
                                            FilteredBooksView(
                                                title: series.series,
                                                filterType: .series(series.series)
                                            )
                                        } label: {
                                            SeriesSearchResult(series: series)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Authors Section
                            if !authorResults.isEmpty {
                                SearchSection(title: "Authors", count: authorResults.count) {
                                    ForEach(authorResults.prefix(5)) { author in
                                        NavigationLink {
                                            FilteredBooksView(
                                                title: author.author,
                                                filterType: .author(author.author)
                                            )
                                        } label: {
                                            AuthorSearchResult(author: author)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 100)
                    }
                    .navigationDestination(for: Audiobook.self) { audiobook in
                        AudiobookDetailView(audiobook: audiobook)
                    }
                }
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search audiobooks, series, authors")
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await search(query: newValue)
            }
        }
    }

    private func search(query: String) async {
        guard !query.isEmpty else {
            bookResults = []
            seriesResults = []
            authorResults = []
            return
        }

        isSearching = true

        do {
            // Fetch all data in parallel
            async let books = api?.getAudiobooks(search: query)
            async let series = api?.getSeries()
            async let authors = api?.getAuthors()

            bookResults = try await books ?? []

            // Filter series that match the query
            let allSeries = try await series ?? []
            let queryLower = query.lowercased()
            seriesResults = allSeries.filter { $0.series.lowercased().contains(queryLower) }

            // Filter authors that match the query
            let allAuthors = try await authors ?? []
            authorResults = allAuthors.filter { $0.author.lowercased().contains(queryLower) }
        } catch {
            print("Search error: \(error)")
        }

        isSearching = false
    }
}

// MARK: - Search Section
struct SearchSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.sapphoHeadline)
                    .foregroundColor(.sapphoTextHigh)

                Text("(\(count))")
                    .font(.sapphoCaption)
                    .foregroundColor(.sapphoTextMuted)
            }

            VStack(spacing: 8) {
                content
            }
        }
    }
}

// MARK: - Book Search Result
struct BookSearchResult: View {
    @Environment(\.sapphoAPI) private var api
    let audiobook: Audiobook

    var body: some View {
        HStack(spacing: 12) {
            // Cover
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

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(audiobook.title)
                    .font(.sapphoBody)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let author = audiobook.author {
                        Text(author)
                    }
                    if let series = audiobook.series {
                        Text("•")
                        Text(series)
                    }
                }
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(10)
    }
}

// MARK: - Series Search Result
struct SeriesSearchResult: View {
    let series: SeriesInfo

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 20))
                .foregroundColor(.sapphoPrimary)
                .frame(width: 48, height: 48)
                .background(Color.sapphoPrimary.opacity(0.2))
                .cornerRadius(6)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(series.series)
                    .font(.sapphoBody)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(1)

                Text("\(series.bookCount) \(series.bookCount == 1 ? "book" : "books")")
                    .font(.sapphoSmall)
                    .foregroundColor(.sapphoTextMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(10)
    }
}

// MARK: - Author Search Result
struct AuthorSearchResult: View {
    let author: AuthorInfo

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundColor(.sapphoSecondary)
                .frame(width: 48, height: 48)
                .background(Color.sapphoSecondary.opacity(0.2))
                .cornerRadius(6)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(author.author)
                    .font(.sapphoBody)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(1)

                Text("\(author.bookCount) \(author.bookCount == 1 ? "book" : "books")")
                    .font(.sapphoSmall)
                    .foregroundColor(.sapphoTextMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(10)
    }
}

// MARK: - All Books Search Results
struct AllBooksSearchResults: View {
    let books: [Audiobook]
    let searchText: String

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(books) { audiobook in
                    NavigationLink {
                        AudiobookDetailView(audiobook: audiobook)
                    } label: {
                        BookSearchResult(audiobook: audiobook)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Color.sapphoBackground)
        .navigationTitle("Results for \"\(searchText)\"")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    SearchView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
