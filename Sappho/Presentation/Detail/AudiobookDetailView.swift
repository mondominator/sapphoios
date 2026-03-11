import SwiftUI

struct AudiobookDetailView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss

    let audiobook: Audiobook

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
                // Cover with overlays (tap to play)
                coverSection
                    .padding(.top, 16)

                // Rating Section (directly under cover)
                ratingSection

                // Chapters and More menu row
                chaptersMenuRow

                // Play Button
                playButton

                // Progress Section (if has progress)
                progressSection

                // Title and Metadata
                titleMetadataSection

                // Description
                descriptionSection
            }
            .padding(.bottom, 32)
        }
        .background(Color.sapphoBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            switch downloadState {
            case .notDownloaded, .failed:
                Button("Download") {
                    handleDownloadTap()
                }
            case .downloading:
                Button("Cancel Download", role: .destructive) {
                    handleDownloadTap()
                }
            case .downloaded:
                Button("Remove Download", role: .destructive) {
                    handleDownloadTap()
                }
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
    private var coverSection: some View {
        Button {
            Task {
                await audioPlayer.play(audiobook: displayBook)
            }
            showPlayer = true
        } label: {
            ZStack {
                // Cover Image
                CoverImage(audiobookId: displayBook.id, cornerRadius: 0)
                    .frame(width: 280, height: 280)

                // Play overlay
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .offset(x: 2) // Visual centering for play icon
                    )

                // Favorite button (top right)
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            Task { await toggleFavorite() }
                        } label: {
                            Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(isFavorite ? .sapphoPrimary : .white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(12)
                    }
                    Spacer()
                }

                // Progress bar (bottom)
                if progressPercent > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                                Rectangle()
                                    .fill(Color.sapphoPrimary)
                                    .frame(width: geo.size.width * progressPercent)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .frame(width: 280, height: 280)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(.plain)
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

    // MARK: - Chapters and Menu Row
    private var chaptersMenuRow: some View {
        HStack(spacing: 12) {
            // Chapters button
            if let chapters = displayBook.chapters, !chapters.isEmpty {
                Button {
                    showChaptersSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16))
                        Text("\(chapters.count) Chapter\(chapters.count == 1 ? "" : "s")")
                            .font(.sapphoSubheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.sapphoTextHigh)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.sapphoSurface)
                    .cornerRadius(10)
                }
            }

            // More menu button
            Button {
                showMoreMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.sapphoTextHigh)
                    .frame(width: 48, height: 48)
                    .background(Color.sapphoSurface)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Play Button
    private var playButton: some View {
        HStack(spacing: 12) {
            // Play/Continue button
            Button {
                Task {
                    await audioPlayer.play(audiobook: displayBook)
                }
                showPlayer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                    Text(isCurrentlyPlaying ? "Pause" : (hasProgress ? "Continue" : "Play"))
                        .font(.sapphoSubheadline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.sapphoPrimary)
                .cornerRadius(12)
            }

            // Download button
            Button {
                handleDownloadTap()
            } label: {
                VStack(spacing: 4) {
                    downloadIcon
                    Text(downloadLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.sapphoTextMuted)
                }
                .frame(width: 64, height: 56)
                .background(Color.sapphoSurface)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
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
            VStack(alignment: .leading, spacing: 12) {
                if let author = displayBook.author {
                    MetadataRow(label: "Author", value: author)
                }

                if let narrator = displayBook.narrator {
                    MetadataRow(label: "Narrator", value: narrator)
                }

                if let series = displayBook.series {
                    let seriesText = series + (displayBook.seriesPosition.map { " #\(Int($0))" } ?? "")
                    MetadataRow(label: "Series", value: seriesText)
                }

                if let genre = displayBook.genre {
                    MetadataRow(label: "Genre", value: genre)
                }

                if let year = displayBook.publishYear {
                    MetadataRow(label: "Published", value: String(year))
                }

                if let duration = displayBook.duration {
                    MetadataRow(label: "Duration", value: formatDuration(duration))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
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

// MARK: - Metadata Row
struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.sapphoCaption)
                .foregroundColor(.sapphoTextMuted)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextHigh)

            Spacer()
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
