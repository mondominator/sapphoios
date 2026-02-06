import SwiftUI

struct SearchView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var searchText = ""
    @State private var results: [Audiobook] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if results.isEmpty && !searchText.isEmpty && !isSearching {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "No audiobooks found for \"\(searchText)\""
                    )
                } else if results.isEmpty && searchText.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Search",
                        message: "Search for audiobooks by title, author, or series"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 140), spacing: 16)
                        ], spacing: 16) {
                            ForEach(results) { audiobook in
                                NavigationLink(value: audiobook) {
                                    AudiobookCard(audiobook: audiobook)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
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
            .searchable(text: $searchText, prompt: "Search audiobooks")
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await search(query: newValue)
            }
        }
    }

    private func search(query: String) async {
        guard !query.isEmpty else {
            results = []
            return
        }

        isSearching = true

        do {
            results = try await api?.getAudiobooks(search: query) ?? []
        } catch {
            print("Search error: \(error)")
        }

        isSearching = false
    }
}

#Preview {
    SearchView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
