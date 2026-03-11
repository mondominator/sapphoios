import SwiftUI

enum LibraryTab: String, CaseIterable {
    case all = "All"
    case series = "Series"
    case authors = "Authors"
    case genres = "Genres"
    case collections = "Collections"
}

enum LibrarySortOption: String, CaseIterable {
    case title = "Title"
    case author = "Author"
    case series = "Series"
    case dateAdded = "Date Added"
    case progress = "Progress"

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .author: return "person"
        case .series: return "books.vertical"
        case .dateAdded: return "calendar"
        case .progress: return "chart.bar"
        }
    }
}

struct LibraryView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var selectedTab: LibraryTab = .all
    @State private var audiobooks: [Audiobook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sortOption: LibrarySortOption = .title
    @State private var sortAscending = true

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

                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .all:
                        allBooksView
                    case .series:
                        SeriesListView()
                    case .authors:
                        AuthorsListView()
                    case .genres:
                        GenresListView()
                    case .collections:
                        CollectionsListView()
                    }
                }
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var sortedAudiobooks: [Audiobook] {
        let sorted = audiobooks.sorted { (a: Audiobook, b: Audiobook) -> Bool in
            switch sortOption {
            case .title:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .author:
                let authorA = a.author ?? ""
                let authorB = b.author ?? ""
                return authorA.localizedCaseInsensitiveCompare(authorB) == .orderedAscending
            case .series:
                let seriesA = a.series ?? ""
                let seriesB = b.series ?? ""
                if seriesA.isEmpty && !seriesB.isEmpty { return false }
                if !seriesA.isEmpty && seriesB.isEmpty { return true }
                return seriesA.localizedCaseInsensitiveCompare(seriesB) == .orderedAscending
            case .dateAdded:
                return a.id < b.id
            case .progress:
                let progressA = Double(a.progress?.position ?? 0) / Double(max(a.duration ?? 1, 1))
                let progressB = Double(b.progress?.position ?? 0) / Double(max(b.duration ?? 1, 1))
                return progressA < progressB
            }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    @ViewBuilder
    private var allBooksView: some View {
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
                    title: "No Audiobooks",
                    message: "Your library is empty."
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Sort controls
                        HStack(spacing: 12) {
                            Menu {
                                ForEach(LibrarySortOption.allCases, id: \.self) { option in
                                    Button {
                                        if sortOption == option {
                                            sortAscending.toggle()
                                        } else {
                                            sortOption = option
                                            sortAscending = true
                                        }
                                    } label: {
                                        Label {
                                            Text(option.rawValue)
                                        } icon: {
                                            if sortOption == option {
                                                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: sortOption.icon)
                                        .font(.system(size: 14))
                                    Text(sortOption.rawValue)
                                        .font(.sapphoCaption)
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(.sapphoTextMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.sapphoSurface)
                                .cornerRadius(8)
                            }

                            Spacer()

                            Text("\(audiobooks.count) books")
                                .font(.sapphoCaption)
                                .foregroundColor(.sapphoTextMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        // Grid of audiobooks
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 140), spacing: 16)
                        ], spacing: 16) {
                            ForEach(sortedAudiobooks) { audiobook in
                                NavigationLink(value: audiobook) {
                                    AudiobookCard(audiobook: audiobook)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 100) // Space for mini player
                    }
                }
                .refreshable {
                    await loadData()
                }
                .navigationDestination(for: Audiobook.self) { audiobook in
                    AudiobookDetailView(audiobook: audiobook)
                }
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            audiobooks = try await api?.getAudiobooks() ?? []
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
