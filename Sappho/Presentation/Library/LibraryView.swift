import SwiftUI

// MARK: - Navigation State

enum LibraryNavigationView: Hashable {
    case series
    case authors
    case genres
    case collections
    case readingList
    case allBooks
}

enum LibrarySortOption: String, CaseIterable {
    case title = "Title"
    case author = "Author"
    case series = "Series"
    case dateAdded = "Date Added"
    case progress = "Progress"
    case duration = "Duration"
    case rating = "Rating"

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .author: return "person"
        case .series: return "books.vertical"
        case .dateAdded: return "calendar"
        case .progress: return "chart.bar"
        case .duration: return "clock"
        case .rating: return "star"
        }
    }
}

enum LibraryFilterOption: String, CaseIterable {
    case all = "All"
    case hideFinished = "Hide Finished"
    case inProgress = "In Progress"
    case notStarted = "Not Started"
    case finished = "Finished"
}

// MARK: - Library View

struct LibraryView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AuthRepository.self) private var authRepository

    @Binding var navigationPath: NavigationPath
    @State private var seriesCount = 0
    @State private var authorsCount = 0
    @State private var genresCount = 0
    @State private var collectionsCount = 0
    @State private var readingListCount = 0
    @State private var totalBooks = 0
    @State private var isLoading = true
    @State private var showUpload = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            categoriesView
                .navigationDestination(for: LibraryNavigationView.self) { destination in
                    Group {
                        switch destination {
                        case .series:
                            SeriesListView()
                                .navigationTitle("Series")
                                .navigationBarTitleDisplayMode(.inline)
                        case .authors:
                            AuthorsListView()
                                .navigationTitle("Authors")
                                .navigationBarTitleDisplayMode(.inline)
                        case .genres:
                            GenresListView()
                                .navigationTitle("Genres")
                                .navigationBarTitleDisplayMode(.inline)
                        case .collections:
                            CollectionsListView()
                                .navigationTitle("Collections")
                                .navigationBarTitleDisplayMode(.inline)
                        case .readingList:
                            ReadingListView()
                        case .allBooks:
                            AllBooksView()
                        }
                    }
                    .background(Color.sapphoBackground)
                    .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                }
                .background(Color.sapphoBackground)
                .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .sheet(isPresented: $showUpload) {
                    UploadView()
                }
        }
    }

    // MARK: - Categories Hub

    private var categoriesView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.sapphoTitle)
                        .foregroundColor(.sapphoTextHigh)

                    if totalBooks > 0 {
                        Text("\(totalBooks) audiobooks in your collection")
                            .font(.sapphoBody)
                            .foregroundColor(.sapphoTextMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Series - Full width hero card
                CategoryCardLarge(
                    title: "Series",
                    count: seriesCount,
                    icon: "books.vertical.fill",
                    gradientColors: [Color.sapphoCategoryBlueStart, Color.sapphoCategoryBlueEnd]
                ) {
                    navigationPath.append(LibraryNavigationView.series)
                }

                // Authors & Genres - Two column
                HStack(spacing: 12) {
                    CategoryCardMedium(
                        title: "Authors",
                        count: authorsCount,
                        icon: "person.2.fill",
                        gradientColors: [Color.sapphoCategoryBlueStart, Color.sapphoCategoryBlueEnd]
                    ) {
                        navigationPath.append(LibraryNavigationView.authors)
                    }

                    CategoryCardMedium(
                        title: "Genres",
                        count: genresCount,
                        icon: "tag.fill",
                        gradientColors: [Color.sapphoCategoryBlueStart, Color.sapphoCategoryBlueEnd]
                    ) {
                        navigationPath.append(LibraryNavigationView.genres)
                    }
                }

                // Collections & Reading List - Two column (teal)
                HStack(spacing: 12) {
                    CategoryCardMedium(
                        title: "Collections",
                        count: collectionsCount,
                        icon: "folder.fill",
                        gradientColors: [Color.sapphoCategoryTealStart, Color.sapphoCategoryTealEnd]
                    ) {
                        navigationPath.append(LibraryNavigationView.collections)
                    }

                    CategoryCardMedium(
                        title: "Reading List",
                        count: readingListCount,
                        icon: "bookmark.fill",
                        gradientColors: [Color.sapphoCategoryTealStart, Color.sapphoCategoryTealEnd]
                    ) {
                        navigationPath.append(LibraryNavigationView.readingList)
                    }
                }

                // All Books - Wide card (gray)
                CategoryCardWide(
                    title: "All Books",
                    icon: "square.grid.2x2.fill",
                    gradientColors: [Color.sapphoCategoryGrayStart, Color.sapphoCategoryGrayEnd]
                ) {
                    navigationPath.append(LibraryNavigationView.allBooks)
                }

                // Upload - Wide card (green, admin only)
                if authRepository.isAdmin {
                    CategoryCardWide(
                        title: "Upload",
                        icon: "square.and.arrow.up.fill",
                        gradientColors: [Color.sapphoSuccess, Color.sapphoSuccess.opacity(0.7)]
                    ) {
                        showUpload = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .background(Color.sapphoBackground)
        .refreshable {
            await loadCounts()
        }
        .task {
            await loadCounts()
        }
    }

    // MARK: - Load Counts

    private func loadCounts() async {
        // Load each count independently so one failure doesn't block others
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                if let s = try? await api?.getSeries() {
                    await MainActor.run { seriesCount = s.count }
                }
            }
            group.addTask {
                if let a = try? await api?.getAuthors() {
                    await MainActor.run { authorsCount = a.count }
                }
            }
            group.addTask {
                if let g = try? await api?.getGenres() {
                    await MainActor.run { genresCount = g.count }
                }
            }
            group.addTask {
                if let c = try? await api?.getCollections() {
                    await MainActor.run { collectionsCount = c.count }
                }
            }
            group.addTask {
                if let f = try? await api?.getFavorites() {
                    await MainActor.run { readingListCount = f.count }
                }
            }
            group.addTask {
                if let b = try? await api?.getAudiobooks() {
                    await MainActor.run { totalBooks = b.count }
                }
            }
        }

        isLoading = false
    }
}

// MARK: - Category Card Large (Full Width Hero)

struct CategoryCardLarge: View {
    let title: String
    let count: Int
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.sapphoTitleSmall)
                        .foregroundColor(.white)
                    Text("\(count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.sapphoTitle)
                        .foregroundColor(.white)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityHint("Double tap to browse \(title.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Category Card Medium (Half Width)

struct CategoryCardMedium: View {
    let title: String
    let count: Int
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.sapphoTitleMedium)
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count)")
                        .font(.sapphoTitle)
                        .foregroundColor(.white)
                    Text(title)
                        .font(.sapphoDetailMedium)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 160)
            .background(
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityHint("Double tap to browse \(title.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Category Card Wide (Full Width, Short)

struct CategoryCardWide: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.sapphoTitleMedium)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sapphoHeadlineMedium)
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sapphoCaption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.sapphoIconSmall)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to open \(title.lowercased())")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - All Books View

struct AllBooksView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var audiobooks: [Audiobook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sortOption: LibrarySortOption = .title
    @State private var sortAscending = true
    @State private var filterOption: LibraryFilterOption = .all

    private var filteredAudiobooks: [Audiobook] {
        switch filterOption {
        case .all:
            return audiobooks
        case .hideFinished:
            return audiobooks.filter { $0.progress?.completed != 1 }
        case .inProgress:
            return audiobooks.filter { ($0.progress?.position ?? 0) > 0 && $0.progress?.completed != 1 }
        case .notStarted:
            return audiobooks.filter { ($0.progress?.position ?? 0) == 0 && $0.progress?.completed != 1 }
        case .finished:
            return audiobooks.filter { $0.progress?.completed == 1 }
        }
    }

    private var sortedAudiobooks: [Audiobook] {
        let sorted = filteredAudiobooks.sorted { (a: Audiobook, b: Audiobook) -> Bool in
            switch sortOption {
            case .title:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .author:
                return (a.author ?? "").localizedCaseInsensitiveCompare(b.author ?? "") == .orderedAscending
            case .series:
                let sa = a.series ?? "", sb = b.series ?? ""
                if sa.isEmpty && !sb.isEmpty { return false }
                if !sa.isEmpty && sb.isEmpty { return true }
                return sa.localizedCaseInsensitiveCompare(sb) == .orderedAscending
            case .dateAdded:
                return a.id < b.id
            case .progress:
                let pa = Double(a.progress?.position ?? 0) / Double(max(a.duration ?? 1, 1))
                let pb = Double(b.progress?.position ?? 0) / Double(max(b.duration ?? 1, 1))
                return pa < pb
            case .duration:
                return (a.duration ?? 0) < (b.duration ?? 0)
            case .rating:
                return (a.userRating ?? a.averageRating ?? 0) < (b.userRating ?? b.averageRating ?? 0)
            }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

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
                    title: "No Audiobooks",
                    message: "Your library is empty."
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Sort and filter controls
                        HStack(spacing: 8) {
                            // Sort dropdown
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
                                    Text("Sort")
                                        .font(.sapphoIconMini)
                                        .foregroundColor(.sapphoTextMuted)
                                    Text(sortOption.rawValue)
                                        .font(.sapphoDetail)
                                        .foregroundColor(.white)
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        .font(.sapphoTiny)
                                        .foregroundColor(.sapphoTextMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.sapphoSurface)
                                .cornerRadius(8)
                            }

                            // Filter dropdown
                            Menu {
                                ForEach(LibraryFilterOption.allCases, id: \.self) { option in
                                    Button {
                                        filterOption = option
                                    } label: {
                                        Label {
                                            Text(option.rawValue)
                                        } icon: {
                                            if filterOption == option {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Show")
                                        .font(.sapphoIconMini)
                                        .foregroundColor(.sapphoTextMuted)
                                    Text(filterOption.rawValue)
                                        .font(.sapphoDetail)
                                        .foregroundColor(.white)
                                    Image(systemName: "chevron.down")
                                        .font(.sapphoTiny)
                                        .foregroundColor(.sapphoTextMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.sapphoSurface)
                                .cornerRadius(8)
                            }

                            Spacer()

                            Text("\(sortedAudiobooks.count) books")
                                .font(.sapphoCaption)
                                .foregroundColor(.sapphoTextMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        // Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(sortedAudiobooks) { audiobook in
                                NavigationLink(value: audiobook) {
                                    AllBooksGridItem(audiobook: audiobook)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100)
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
        .navigationTitle("\(sortedAudiobooks.count) Books")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            audiobooks = try await api?.getAudiobooks(limit: 10000) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - All Books Grid Item

struct AllBooksGridItem: View {
    let audiobook: Audiobook

    private var progressPercent: Double {
        guard let progress = audiobook.progress,
              let duration = audiobook.duration,
              duration > 0 else { return 0 }
        return Double(progress.position) / Double(duration)
    }

    private var isCompleted: Bool {
        audiobook.progress?.completed == 1
    }

    var body: some View {
        ZStack {
            // Cover
            CoverImage(audiobookId: audiobook.id, cornerRadius: 0)
                .aspectRatio(1, contentMode: .fill)

            // Overlays
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Spacer()

                    // Reading list ribbon
                    if audiobook.isQueued == true && !isCompleted {
                        BookmarkRibbon()
                            .fill(Color.sapphoPrimary)
                            .frame(width: 28, height: 28)
                    }

                    // Completed badge
                    if isCompleted {
                        ZStack {
                            Circle()
                                .fill(Color.sapphoSuccess)
                                .frame(width: 20, height: 20)
                            Image(systemName: "checkmark")
                                .font(.sapphoTinyBold)
                                .foregroundColor(.white)
                        }
                        .padding(4)
                    }
                }

                Spacer()

                // Rating badge (bottom-right)
                if let rating = audiobook.userRating ?? audiobook.averageRating, rating > 0 {
                    HStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.sapphoMicro)
                                .foregroundColor(.sapphoRating)
                            Text(String(format: "%.0f", rating))
                                .font(.sapphoTinySemibold)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(4)
                        .padding(4)
                    }
                }

                // Progress bar
                if progressPercent > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.7))
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: isCompleted
                                            ? [Color.sapphoSuccess, Color.sapphoSuccessLight]
                                            : [Color.sapphoPrimaryLight, Color.sapphoPrimaryLighter],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progressPercent)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(audiobook.title), by \(audiobook.author ?? "Unknown Author")\(isCompleted ? ", Completed" : progressPercent > 0 ? ", \(Int(progressPercent * 100)) percent complete" : "")\(audiobook.isQueued == true ? ", In reading list" : "")")
        .accessibilityHint("Double tap to view details")
    }
}

#Preview {
    LibraryView(navigationPath: .constant(NavigationPath()))
        .environment(AuthRepository())
        .environment(AudioPlayerService())
}
