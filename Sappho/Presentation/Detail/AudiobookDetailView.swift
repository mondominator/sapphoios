import SwiftUI

struct AudiobookDetailView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss

    let audiobook: Audiobook
    var onAuthorTap: ((String) -> Void)? = nil
    var onSeriesTap: ((String) -> Void)? = nil

    @State private var fullAudiobook: Audiobook?
    @State private var isFavorite: Bool = false
    @State private var isLoading = true
    @State private var showPlayer = false
    @State private var userRating: Int?
    @State private var averageRating: AverageRating?
    @State private var showRatingSheet = false
    @State private var showCollectionsSheet = false
    @State private var collectionsForBook: [CollectionForBook] = []
    @State private var showShareSheet = false
    @State private var showChaptersSheet = false
    @State private var showMoreMenu = false
    @State private var descriptionExpanded = false
    @State private var authorToNavigate: String = ""
    @State private var seriesToNavigate: String = ""
    @State private var showAuthorView = false
    @State private var showSeriesView = false

    private var downloadManager: DownloadManager { DownloadManager.shared }
    private var downloadState: DownloadState {
        downloadManager.downloads[displayBook.id] ?? .notDownloaded
    }

    private var displayBook: Audiobook {
        fullAudiobook ?? audiobook
    }

    private var progressPercent: Double {
        guard let progress = displayBook.progress,
              let duration = displayBook.duration,
              duration > 0 else { return 0 }
        return Double(progress.position) / Double(duration)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cover with overlays
                coverSection
                    .padding(.top, 16)

                // Rating Section (directly under cover)
                ratingSection

                // Action row: Play + Download + Overflow (matches Android layout)
                actionRow

                // Progress Section (if has progress)
                progressSection

                // Title and Metadata
                titleMetadataSection

                // Description
                descriptionSection
            }
            .padding(.bottom, 120) // Space for mini player
        }
        .background(Color.sapphoBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showAuthorView) {
            FilteredBooksView(title: authorToNavigate, filterType: .author(authorToNavigate))
        }
        .navigationDestination(isPresented: $showSeriesView) {
            FilteredBooksView(title: seriesToNavigate, filterType: .series(seriesToNavigate))
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        .sheet(isPresented: $showCollectionsSheet) {
            AddToCollectionSheet(
                audiobookId: displayBook.id,
                collectionsForBook: $collectionsForBook
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showChaptersSheet) {
            ChaptersSheet(
                chapters: displayBook.chapters ?? [],
                currentChapter: nil,
                onSelect: { chapter in
                    Task {
                        await audioPlayer.play(audiobook: displayBook, startPosition: chapter.startTime)
                    }
                    showChaptersSheet = false
                    showPlayer = true
                }
            )
        }
        .confirmationDialog("More Options", isPresented: $showMoreMenu, titleVisibility: .hidden) {
            if let chapters = displayBook.chapters, !chapters.isEmpty {
                Button("\(chapters.count) Chapters") {
                    showChaptersSheet = true
                }
            }
            Button("Add to Collection") {
                showCollectionsSheet = true
            }
            Button("Mark Finished") {
                Task { await markFinished() }
            }
            if hasProgress {
                Button("Clear Progress", role: .destructive) {
                    Task { await clearProgress() }
                }
            }
            Button("Share") {
                showShareSheet = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await loadFullAudiobook()
            await loadRating()
            await loadCollections()
        }
    }

    // MARK: - Cover Section
    private var isCompleted: Bool {
        displayBook.progress?.completed == 1
    }

    private var coverSection: some View {
        ZStack {
            // Cover Image
            CoverImage(audiobookId: displayBook.id, cornerRadius: 0)
                .frame(width: 320, height: 320)

            // Bookmark button (top right)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(isFavorite ? .sapphoPrimary : .white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(12)
                }
                Spacer()
            }

            // Progress bar (bottom of cover)
            if progressPercent > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: isCompleted
                                            ? [Color.sapphoSuccess.opacity(0.8), Color.sapphoSuccess]
                                            : [Color.sapphoPrimary.opacity(0.8), Color.sapphoPrimary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * min(progressPercent, 1.0))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12,
                            topTrailingRadius: 0
                        )
                    )
                }
            }
        }
        .frame(width: 320, height: 320)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }

    // MARK: - Rating Section
    private var ratingSection: some View {
        VStack(spacing: 8) {
            // Star rating (tap same star to clear)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        if userRating == star {
                            Task { await clearRating() }
                        } else {
                            Task { await setRating(star) }
                        }
                    } label: {
                        Image(systemName: star <= (userRating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundColor(star <= (userRating ?? 0) ? .sapphoWarning : .sapphoTextMuted)
                    }
                }
            }

            // Rating info
            HStack(spacing: 4) {
                if userRating != nil {
                    Text("Your rating")
                        .foregroundColor(.sapphoTextMuted)
                } else {
                    Text("Tap to rate")
                        .foregroundColor(.sapphoTextMuted)
                }

                if let avg = averageRating, avg.count > 0 {
                    Text("·")
                        .foregroundColor(.sapphoTextMuted)
                    Image(systemName: "star.fill")
                        .foregroundColor(.sapphoWarning)
                        .font(.system(size: 12))
                    Text(String(format: "%.1f", avg.average ?? 0))
                        .foregroundColor(.sapphoTextHigh)
                    Text("(\(avg.count))")
                        .foregroundColor(.sapphoTextMuted)
                }
            }
            .font(.sapphoCaption)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Action Row (Play + Download + Overflow)
    private var actionRow: some View {
        HStack(spacing: 12) {
            // Play/Continue button (expands to fill)
            Button {
                if isCurrentlyPlaying {
                    audioPlayer.togglePlayPause()
                } else {
                    Task {
                        await audioPlayer.play(audiobook: displayBook)
                    }
                    showPlayer = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                    Text(isCurrentlyPlaying ? "Pause" : (hasProgress ? "Continue" : "Play"))
                        .font(.sapphoSubheadline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    isCurrentlyPlaying
                        ? Color.sapphoPrimary.opacity(0.2)
                        : Color.sapphoSuccess.opacity(0.2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .cornerRadius(12)
            }

            // Download button (icon only, 48x48)
            Button {
                handleDownloadTap()
            } label: {
                downloadIcon
                    .frame(width: 48, height: 52)
                    .background(Color.sapphoSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(12)
            }

            // Overflow menu button (icon only, 48x48)
            Button {
                showMoreMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.sapphoTextHigh)
                    .frame(width: 48, height: 52)
                    .background(Color.sapphoSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Progress Section
    @ViewBuilder
    private var progressSection: some View {
        if let progress = displayBook.progress, let duration = displayBook.duration, duration > 0, progress.position > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Progress")
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)

                VStack(spacing: 8) {
                    // Progress info
                    HStack {
                        if progress.completed == 1 {
                            Text("Completed")
                                .foregroundColor(.sapphoSuccess)
                        } else {
                            Text("\(formatDuration(progress.position)) listened")
                                .foregroundColor(.sapphoTextHigh)
                            Text("of \(formatDuration(duration)) total")
                                .foregroundColor(.sapphoTextMuted)
                        }
                        Spacer()
                        if progress.completed != 1 {
                            Text("\(Int(progressPercent * 100))%")
                                .foregroundColor(.sapphoTextMuted)
                        }
                    }
                    .font(.sapphoCaption)

                    // Progress bar
                    if progress.completed != 1 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.sapphoSurface)
                                Rectangle()
                                    .fill(Color.sapphoPrimary)
                                    .frame(width: geo.size.width * progressPercent)
                            }
                        }
                        .frame(height: 4)
                        .cornerRadius(2)
                    }

                    // Current chapter info
                    if let chapters = displayBook.chapters, !chapters.isEmpty {
                        let currentChapter = chapters.last { $0.startTime <= Double(progress.position) }
                        if let chapter = currentChapter {
                            let chapterIndex = chapters.firstIndex(where: { $0.startTime == chapter.startTime }) ?? 0
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.sapphoPrimary)
                                Text(chapter.title ?? "Chapter \(chapterIndex + 1)")
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoTextMuted)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(chapterIndex + 1) of \(chapters.count)")
                                    .font(.sapphoSmall)
                                    .foregroundColor(.sapphoTextMuted)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.sapphoSurface)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Title and Metadata Section
    private var titleMetadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(displayBook.title)
                .font(.sapphoTitle)
                .foregroundColor(.sapphoTextHigh)

            // Metadata grid
            VStack(alignment: .leading, spacing: 16) {
                if let author = displayBook.author {
                    MetadataItem(label: "AUTHOR", value: author, isLink: true, onTap: {
                        if let callback = onAuthorTap {
                            callback(author)
                        } else {
                            authorToNavigate = author
                            showAuthorView = true
                        }
                    })
                }

                if let narrator = displayBook.narrator {
                    MetadataItem(label: "NARRATOR", value: narrator)
                }

                if let series = displayBook.series {
                    let posText = displayBook.seriesPosition.map { " (Book \(formatSeriesPosition($0)))" } ?? ""
                    MetadataItem(label: "SERIES", value: series + posText, isLink: true, onTap: {
                        if let callback = onSeriesTap {
                            callback(series)
                        } else {
                            seriesToNavigate = series
                            showSeriesView = true
                        }
                    })
                }

                if let genre = displayBook.genre {
                    MetadataItem(label: "GENRE", value: genre)
                }

                if let year = displayBook.publishYear {
                    MetadataItem(label: "PUBLISHED", value: String(year))
                }

                if let duration = displayBook.duration {
                    MetadataItem(label: "DURATION", value: formatDuration(duration))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private func formatSeriesPosition(_ position: Float) -> String {
        if position == floor(position) {
            return String(format: "%.0f", position)
        }
        return String(format: "%.1f", position)
    }

    // MARK: - Description Section
    @ViewBuilder
    private var descriptionSection: some View {
        if let description = displayBook.description, !description.isEmpty {
            let cleanText = stripHTML(description)
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .font(.sapphoHeadline)
                    .foregroundColor(.sapphoTextHigh)

                Text(cleanText)
                    .font(.sapphoBody)
                    .foregroundColor(.sapphoTextMedium)
                    .lineLimit(descriptionExpanded ? nil : 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        descriptionExpanded.toggle()
                    }
                } label: {
                    Text(descriptionExpanded ? "Show Less" : "Show More")
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
    }

    private func stripHTML(_ html: String) -> String {
        guard html.contains("<") else { return html }
        // Replace common HTML entities
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Strip remaining HTML tags
        while let range = text.range(of: "<[^>]+>", options: .regularExpression) {
            text.removeSubrange(range)
        }
        // Collapse multiple newlines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentAudiobook?.id == displayBook.id && audioPlayer.isPlaying
    }

    private var hasProgress: Bool {
        displayBook.progress?.position ?? 0 > 0
    }

    @ViewBuilder
    private var downloadIcon: some View {
        switch downloadState {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundColor(.sapphoTextMuted)
        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.sapphoSurface, lineWidth: 3)
                ProgressView(value: progress)
                    .progressViewStyle(CircularProgressViewStyle(tint: .sapphoPrimary))
            }
            .frame(width: 24, height: 24)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.sapphoSuccess)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 20))
                .foregroundColor(.sapphoError)
        }
    }

    private var downloadLabel: String {
        switch downloadState {
        case .notDownloaded:
            return "Download"
        case .downloading(let progress):
            return "\(Int(progress * 100))%"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Retry"
        }
    }

    private func handleDownloadTap() {
        switch downloadState {
        case .notDownloaded, .failed:
            downloadManager.download(audiobook: displayBook)
        case .downloading:
            downloadManager.cancelDownload(audiobookId: displayBook.id)
        case .downloaded:
            // Show option to remove download
            downloadManager.removeDownload(audiobookId: displayBook.id)
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = []

        // Create share text
        var shareText = displayBook.title
        if let author = displayBook.author {
            shareText += " by \(author)"
        }
        if let series = displayBook.series {
            shareText += "\n\(series)"
            if let position = displayBook.seriesPosition {
                shareText += " #\(Int(position))"
            }
        }
        items.append(shareText)

        return items
    }

    private func loadFullAudiobook() async {
        do {
            fullAudiobook = try await api?.getAudiobook(id: audiobook.id)
            isFavorite = fullAudiobook?.isFavorite ?? false
        } catch {
            print("Failed to load audiobook: \(error)")
        }
        isLoading = false
    }

    private func toggleFavorite() async {
        do {
            let response = try await api?.toggleFavorite(audiobookId: displayBook.id)
            isFavorite = response?.isFavorite ?? isFavorite
        } catch {
            print("Failed to toggle favorite: \(error)")
        }
    }

    private func loadRating() async {
        do {
            let rating = try await api?.getUserRating(audiobookId: audiobook.id)
            userRating = rating?.rating
            averageRating = try await api?.getAverageRating(audiobookId: audiobook.id)
        } catch {
            print("Failed to load rating: \(error)")
        }
    }

    private func setRating(_ rating: Int) async {
        do {
            let response = try await api?.setRating(audiobookId: displayBook.id, rating: rating)
            userRating = response?.rating
            // Reload average rating
            averageRating = try await api?.getAverageRating(audiobookId: displayBook.id)
        } catch {
            print("Failed to set rating: \(error)")
        }
    }

    private func clearRating() async {
        do {
            let _ = try await api?.setRating(audiobookId: displayBook.id, rating: nil)
            userRating = nil
            // Reload average rating
            averageRating = try await api?.getAverageRating(audiobookId: displayBook.id)
        } catch {
            print("Failed to clear rating: \(error)")
        }
    }

    private func loadCollections() async {
        do {
            collectionsForBook = try await api?.getCollectionsForBook(audiobookId: audiobook.id) ?? []
        } catch {
            print("Failed to load collections: \(error)")
        }
    }

    private func markFinished() async {
        do {
            try await api?.markFinished(audiobookId: displayBook.id)
            await loadFullAudiobook()
        } catch {
            print("Failed to mark finished: \(error)")
        }
    }

    private func clearProgress() async {
        do {
            try await api?.clearProgress(audiobookId: displayBook.id)
            await loadFullAudiobook()
        } catch {
            print("Failed to clear progress: \(error)")
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

// MARK: - Metadata Item (matches Android style)
struct MetadataItem: View {
    let label: String
    let value: String
    var isLink: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.sapphoTextMuted)
                .tracking(0.5)

            if let onTap = onTap {
                Button(action: onTap) {
                    Text(value)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.sapphoPrimary)
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isLink ? .sapphoPrimary : .sapphoTextHigh)
            }
        }
    }
}

// MARK: - Add to Collection Sheet
struct AddToCollectionSheet: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss
    let audiobookId: Int
    @Binding var collectionsForBook: [CollectionForBook]

    @State private var allCollections: [Collection] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingView()
                } else if allCollections.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            icon: "folder",
                            title: "No Collections",
                            message: "Create a collection first to add this book to it."
                        )
                    }
                } else {
                    List {
                        ForEach(allCollections) { collection in
                            let isInCollection = collectionsForBook.first { $0.id == collection.id }?.isInCollection ?? false

                            Button {
                                Task {
                                    await toggleCollection(collection, isInCollection: isInCollection)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: isInCollection ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isInCollection ? .sapphoPrimary : .sapphoTextMuted)

                                    VStack(alignment: .leading) {
                                        Text(collection.name)
                                            .foregroundColor(.sapphoTextHigh)

                                        if let desc = collection.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.sapphoSmall)
                                                .foregroundColor(.sapphoTextMuted)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    if collection.isPublic == 1 {
                                        Image(systemName: "globe")
                                            .font(.system(size: 12))
                                            .foregroundColor(.sapphoTextMuted)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.sapphoBackground)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadCollections()
        }
    }

    private func loadCollections() async {
        isLoading = true

        do {
            allCollections = try await api?.getCollections() ?? []
            collectionsForBook = try await api?.getCollectionsForBook(audiobookId: audiobookId) ?? []
        } catch {
            print("Failed to load collections: \(error)")
        }

        isLoading = false
    }

    private func toggleCollection(_ collection: Collection, isInCollection: Bool) async {
        do {
            if isInCollection {
                try await api?.removeFromCollection(collectionId: collection.id, audiobookId: audiobookId)
            } else {
                try await api?.addToCollection(collectionId: collection.id, audiobookId: audiobookId)
            }
            // Refresh the list
            collectionsForBook = try await api?.getCollectionsForBook(audiobookId: audiobookId) ?? []
        } catch {
            print("Failed to toggle collection: \(error)")
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        AudiobookDetailView(audiobook: Audiobook(
            id: 1,
            title: "Sample Book",
            subtitle: nil,
            author: "Author Name",
            narrator: "Narrator Name",
            series: "Sample Series",
            seriesPosition: 1,
            duration: 36000,
            genre: "Fiction",
            tags: nil,
            publishYear: 2024,
            copyrightYear: nil,
            publisher: nil,
            isbn: nil,
            asin: nil,
            language: nil,
            rating: nil,
            userRating: nil,
            averageRating: nil,
            abridged: nil,
            description: "A sample book description.",
            coverImage: nil,
            fileCount: 1,
            isMultiFile: nil,
            createdAt: "",
            progress: nil,
            chapters: nil,
            isFavorite: false
        ))
    }
    .environment(AuthRepository())
    .environment(AudioPlayerService())
}
