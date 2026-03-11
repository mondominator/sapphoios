import SwiftUI

struct GenresListView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var genres: [GenreInfo] = []
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
            } else if genres.isEmpty {
                EmptyStateView(
                    icon: "tag",
                    title: "No Genres",
                    message: "Your library doesn't have any genres yet."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(genres) { genreInfo in
                            NavigationLink {
                                FilteredBooksView(
                                    title: genreInfo.genre,
                                    filterType: .genre(genreInfo.genre)
                                )
                            } label: {
                                GenreCard(genreInfo: genreInfo)
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
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let genresData = api?.getGenres()
            async let booksData = api?.getAudiobooks()

            genres = try await genresData ?? []
            allBooks = try await booksData ?? []

            // Sort genres by book count (descending)
            genres.sort { $0.count > $1.count }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct GenreCard: View {
    @Environment(\.sapphoAPI) private var api
    let genreInfo: GenreInfo

    private var gradientColors: [Color] {
        let hash = abs(genreInfo.genre.hashValue)
        let hue = Double(hash % 360) / 360.0
        return [
            Color(hue: hue, saturation: 0.7, brightness: 0.5),
            Color(hue: hue, saturation: 0.5, brightness: 0.3)
        ]
    }

    private var iconName: String {
        // Map common genres to SF Symbols
        let genre = genreInfo.genre.lowercased()
        if genre.contains("mystery") || genre.contains("thriller") {
            return "magnifyingglass"
        } else if genre.contains("romance") {
            return "heart.fill"
        } else if genre.contains("science") || genre.contains("sci-fi") {
            return "atom"
        } else if genre.contains("fantasy") {
            return "wand.and.stars"
        } else if genre.contains("horror") {
            return "moon.stars.fill"
        } else if genre.contains("history") || genre.contains("historical") {
            return "clock.arrow.circlepath"
        } else if genre.contains("biography") || genre.contains("memoir") {
            return "person.fill"
        } else if genre.contains("business") || genre.contains("finance") {
            return "chart.line.uptrend.xyaxis"
        } else if genre.contains("self-help") || genre.contains("self help") {
            return "brain.head.profile"
        } else if genre.contains("comedy") || genre.contains("humor") {
            return "face.smiling"
        } else if genre.contains("children") || genre.contains("kids") {
            return "figure.and.child.holdinghands"
        } else if genre.contains("fiction") {
            return "book.closed.fill"
        } else if genre.contains("non-fiction") || genre.contains("nonfiction") {
            return "text.book.closed.fill"
        }
        return "tag.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon and title
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(.white)

                Spacer()

                Text("\(genreInfo.count)")
                    .font(.sapphoCaption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
            }

            Spacer()

            Text(genreInfo.genre)
                .font(.sapphoSubheadline)
                .foregroundColor(.white)
                .lineLimit(2)

            Text("\(genreInfo.count) \(genreInfo.count == 1 ? "book" : "books")")
                .font(.sapphoSmall)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .frame(height: 140)
        .background(
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
    }
}

#Preview {
    NavigationStack {
        GenresListView()
    }
    .environment(AuthRepository())
}
