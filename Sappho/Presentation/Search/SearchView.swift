import SwiftUI

struct SearchView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var searchText = ""
    @State private var bookResults: [Audiobook] = []
    @State private var seriesResults: [SeriesInfo] = []
    @State private var authorResults: [AuthorInfo] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var hasResults: Bool {
        !bookResults.isEmpty || !seriesResults.isEmpty || !authorResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom search bar (matches Android)
                SearchBar(text: $searchText, onClear: {
                    searchText = ""
                    bookResults = []
                    seriesResults = []
                    authorResults = []
                })
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Content
                Group {
                    if isSearching && !hasResults {
                        SearchSkeletonView()
                    } else if !hasResults && !searchText.isEmpty && !isSearching {
                        VStack(spacing: 16) {
                            EmptyStateView(
                                icon: "magnifyingglass",
                                title: "No Results",
                                message: "Try searching with different keywords or browse the library"
                            )
                            Button("Clear search") {
                                searchText = ""
                                bookResults = []
                                seriesResults = []
                                authorResults = []
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.sapphoPrimary)
                        }
                    } else if !hasResults && searchText.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "Search",
                            message: "Search for books, series, or authors"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                // Books Section
                                if !bookResults.isEmpty {
                                    SearchSection(title: "Books", count: bookResults.count) {
                                        ForEach(bookResults.prefix(8)) { audiobook in
                                            NavigationLink(value: audiobook) {
                                                BookSearchResult(audiobook: audiobook)
                                            }
                                            .buttonStyle(.plain)
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
            }
            .background(Color.sapphoBackground)
        }
        .onChange(of: searchText) { _, newValue in
            // Debounce search by 300ms
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
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
            async let books = api?.getAudiobooks(search: query)
            async let series = api?.getSeries()
            async let authors = api?.getAuthors()

            bookResults = try await books ?? []

            let queryLower = query.lowercased()
            let allSeries = try await series ?? []
            seriesResults = allSeries.filter { $0.series.lowercased().contains(queryLower) }

            let allAuthors = try await authors ?? []
            authorResults = allAuthors.filter { $0.author.lowercased().contains(queryLower) }
        } catch {
            print("Search error: \(error)")
        }

        isSearching = false
    }
}

// MARK: - Custom Search Bar

struct SearchBar: View {
    @Binding var text: String
    let onClear: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(.sapphoTextMuted)

            TextField("Search books, series, authors...", text: $text)
                .font(.system(size: 16))
                .foregroundColor(.sapphoTextHigh)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.sapphoTextMuted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.118, green: 0.161, blue: 0.231)) // #1E293B
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Search Skeleton

struct SearchSkeletonView: View {
    @State private var shimmerPhase: CGFloat = -1

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.05),
                Color.white.opacity(0.15),
                Color.white.opacity(0.05)
            ],
            startPoint: .init(x: shimmerPhase - 0.5, y: 0.5),
            endPoint: .init(x: shimmerPhase + 0.5, y: 0.5)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.sapphoSurface)
                .frame(width: 80, height: 14)
                .overlay(shimmerGradient)

            // Result row skeletons
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    // Cover skeleton
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.sapphoSurface)
                        .frame(width: 48, height: 48)
                        .overlay(shimmerGradient)

                    VStack(alignment: .leading, spacing: 6) {
                        // Title skeleton
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sapphoSurface)
                            .frame(height: 12)
                            .frame(maxWidth: .infinity)
                            .overlay(shimmerGradient)

                        // Subtitle skeleton
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sapphoSurface)
                            .frame(width: 120, height: 10)
                            .overlay(shimmerGradient)
                    }
                }
                .padding(8)
            }
        }
        .padding(16)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmerPhase = 2
            }
        }
    }
}

// MARK: - Search Section
struct SearchSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
    let audiobook: Audiobook

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(audiobookId: audiobook.id, cornerRadius: 6)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(audiobook.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let author = audiobook.author {
                        Text(author)
                    }
                    if let series = audiobook.series {
                        Text("-")
                        Text(series)
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(8)
        .background(Color.sapphoSurface)
        .cornerRadius(8)
    }
}

// MARK: - Series Search Result
struct SeriesSearchResult: View {
    let series: SeriesInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Color(red: 0.216, green: 0.255, blue: 0.318)) // #374151
                .cornerRadius(6)

            Text(series.series)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.sapphoTextHigh)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(8)
        .background(Color.sapphoSurface)
        .cornerRadius(8)
    }
}

// MARK: - Author Search Result
struct AuthorSearchResult: View {
    let author: AuthorInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(Color(red: 0.216, green: 0.255, blue: 0.318)) // #374151
                .cornerRadius(6)

            Text(author.author)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.sapphoTextHigh)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(8)
        .background(Color.sapphoSurface)
        .cornerRadius(8)
    }
}

#Preview {
    SearchView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
