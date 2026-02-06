import SwiftUI

enum LibraryTab: String, CaseIterable {
    case all = "All"
    case series = "Series"
    case authors = "Authors"
    case genres = "Genres"
    case collections = "Collections"
}

struct LibraryView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var selectedTab: LibraryTab = .all
    @State private var audiobooks: [Audiobook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LibraryTab.allCases, id: \.self) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(.sapphoSubheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedTab == tab ? Color.sapphoPrimary : Color.sapphoSurface)
                                    .foregroundColor(selectedTab == tab ? .white : .sapphoTextMuted)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color.sapphoBackground)

                // Content
                if isLoading {
                    LoadingView()
                } else if let error = errorMessage {
                    ErrorView(message: error) {
                        Task { await loadData() }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 140), spacing: 16)
                        ], spacing: 16) {
                            ForEach(audiobooks) { audiobook in
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
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await loadData()
        }
        .onChange(of: selectedTab) { _, _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            switch selectedTab {
            case .all:
                audiobooks = try await api?.getAudiobooks() ?? []
            case .series, .authors, .genres, .collections:
                // TODO: Implement filtered views
                audiobooks = try await api?.getAudiobooks() ?? []
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    LibraryView()
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
