import SwiftUI

private enum PendingSheet {
    case chapters, collections, share, editChapters, editMetadata
}

struct AudiobookDetailView: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(AuthRepository.self) private var authRepository
    @Environment(\.dismiss) private var dismiss

    let audiobook: Audiobook
    var onAuthorTap: ((String) -> Void)? = nil
    var onSeriesTap: ((String) -> Void)? = nil

    @State private var fullAudiobook: Audiobook?
    @State private var chapters: [Chapter] = []
    @State private var isFavorite: Bool = false
    @State private var isLoading = true
    // Full player is shown via audioPlayer.showFullPlayer (handled by MainView overlay)
    @State private var userRating: Int?
    @State private var averageRating: AverageRating?
    @State private var reviews: [ReviewItem] = []
    @State private var userReviewText: String = ""
    @State private var isSubmittingReview = false
    @State private var showRatingPicker = false
    @State private var showReviews = false
    @FocusState private var isReviewFocused: Bool
    @State private var showCollectionsSheet = false
    @State private var collectionsForBook: [CollectionForBook] = []
    @State private var showShareSheet = false
    @State private var showChaptersSheet = false
    @State private var showMoreMenu = false
    @State private var pendingSheet: PendingSheet?
    @State private var descriptionExpanded = false
    @State private var toastMessage: String?
    @State private var authorToNavigate: String = ""
    @State private var seriesToNavigate: String = ""
    @State private var showAuthorView = false
    @State private var showSeriesView = false
    @State private var isAiConfigured = false
    @State private var recapText: String?
    @State private var isLoadingRecap = false
    @State private var recapError: String?
    @State private var previousBookCompleted = false

    // Admin features
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showChapterEditor = false
    @State private var isRefreshing = false
    @State private var isConverting = false

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

                // Description (with Catch Up button)
                descriptionSection

                // Title and Metadata
                titleMetadataSection
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
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: audioPlayer.showFullPlayer)
        .sheet(isPresented: $showCollectionsSheet) {
            AddToCollectionSheet(
                audiobookId: displayBook.id,
                collectionsForBook: $collectionsForBook
            )
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showEditSheet) {
            EditMetadataSheet(audiobook: displayBook) { updatedBook in
                fullAudiobook = updatedBook
            }
        }
        .sheet(isPresented: $showChapterEditor) {
            EditChaptersSheet(
                audiobookId: displayBook.id,
                chapters: chapters
            ) {
                // Reload chapters after save
                Task {
                    chapters = try await api?.getChapters(audiobookId: displayBook.id) ?? []
                }
            }
        }
        .alert("Delete Audiobook", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await api?.deleteAudiobook(id: displayBook.id)
                    dismiss()
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(displayBook.title)\"? This cannot be undone.")
        }
        .sheet(isPresented: $showChaptersSheet) {
            ChaptersSheet(
                chapters: chapters,
                currentChapter: nil,
                onSelect: { chapter in
                    showChaptersSheet = false
                    Task {
                        await audioPlayer.play(audiobook: displayBook, startPosition: chapter.startTime)
                        audioPlayer.showFullPlayer = true
                    }
                }
            )
        }
        .sheet(isPresented: $showMoreMenu, onDismiss: {
            if let pending = pendingSheet {
                pendingSheet = nil
                switch pending {
                case .chapters:
                    showChaptersSheet = true
                case .collections:
                    showCollectionsSheet = true
                case .share:
                    showShareSheet = true
                case .editChapters:
                    showChapterEditor = true
                case .editMetadata:
                    showEditSheet = true
                }
            }
        }) {
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 20)

                // Menu items
                VStack(spacing: 4) {
                    if !chapters.isEmpty {
                        moreMenuItem(
                            icon: "list.bullet",
                            title: "\(chapters.count) Chapters",
                            subtitle: "Browse & jump to chapters",
                            color: .sapphoPrimary
                        ) {
                            pendingSheet = .chapters
                            showMoreMenu = false
                        }
                    }

                    moreMenuItem(
                        icon: "folder.badge.plus",
                        title: "Add to Collection",
                        subtitle: "Organize your library",
                        color: .sapphoWarning
                    ) {
                        pendingSheet = .collections
                        showMoreMenu = false
                    }

                    moreMenuItem(
                        icon: "checkmark.circle",
                        title: "Mark Finished",
                        subtitle: "Mark as completed",
                        color: .sapphoSuccess
                    ) {
                        showMoreMenu = false
                        Task { await markFinished() }
                    }

                    if hasProgress {
                        moreMenuItem(
                            icon: "xmark.circle",
                            title: "Clear Progress",
                            subtitle: "Reset listening position",
                            color: .sapphoError
                        ) {
                            showMoreMenu = false
                            Task { await clearProgress() }
                        }
                    }

                    // Admin-only features
                    if authRepository.isAdmin {
                        Divider().background(Color.sapphoTextMuted.opacity(0.3)).padding(.vertical, 8)

                        moreMenuItem(
                            icon: "arrow.clockwise",
                            title: isRefreshing ? "Refreshing..." : "Refresh Metadata",
                            subtitle: "Re-extract from file tags",
                            color: .sapphoPrimary
                        ) {
                            showMoreMenu = false
                            Task { await refreshMetadata() }
                        }

                        moreMenuItem(
                            icon: "arrow.triangle.swap",
                            title: isConverting ? "Converting..." : "Convert to M4B",
                            subtitle: "Merge into single audiobook file",
                            color: .sapphoPrimary
                        ) {
                            showMoreMenu = false
                            Task { await convertToM4B() }
                        }

                        if !chapters.isEmpty {
                            moreMenuItem(
                                icon: "list.bullet.indent",
                                title: "Edit Chapters",
                                subtitle: "Rename chapter titles",
                                color: .sapphoPrimary
                            ) {
                                pendingSheet = .editChapters
                                showMoreMenu = false
                            }
                        }

                        Divider().background(Color.sapphoTextMuted.opacity(0.3)).padding(.vertical, 8)

                        moreMenuItem(
                            icon: "trash",
                            title: "Delete Audiobook",
                            subtitle: "Remove from library",
                            color: .sapphoError
                        ) {
                            showMoreMenu = false
                            showDeleteConfirm = true
                        }
                    }

                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.sapphoSurface)
            .presentationDetents([.fraction(authRepository.isAdmin ? 0.75 : (chapters.isEmpty ? 0.38 : 0.45))])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
        }
        .task {
            async let aiCheck: Void = checkAiStatus()
            async let prevCheck: Void = checkPreviousBookStatus()
            await loadFullAudiobook()
            await loadRating()
            await loadReviews()
            await loadCollections()
            _ = await (aiCheck, prevCheck)
        }
        .overlay(alignment: .bottom) {
            if let message = toastMessage {
                Text(message)
                    .font(.sapphoCaption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.sapphoSurface)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
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
                            .font(.sapphoTitleSmall)
                            .foregroundColor(isFavorite ? .sapphoPrimary : .white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(isFavorite ? "In reading list" : "Add to reading list")
                    .accessibilityHint(isFavorite ? "Double tap to remove from reading list" : "Double tap to add to reading list")
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
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(width: 320, height: 320)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cover art for \(displayBook.title)\(progressPercent > 0 ? ", \(Int(progressPercent * 100)) percent complete" : "")")
    }

    // MARK: - Rating Section
    private var reviewCount: Int {
        allReviewsWithText.count
    }

    private var ratingSection: some View {
        VStack(spacing: 12) {
            // Main row: Average rating + Rate button + Comment count
            HStack(spacing: 16) {
                // Show average rating
                if let avg = averageRating, avg.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.sapphoWarning)
                            .font(.sapphoBody)
                        Text(String(format: "%.1f", avg.average ?? 0))
                            .font(.sapphoBodyMedium)
                            .foregroundColor(.sapphoTextHigh)
                    }
                }

                // Rate button - pill style
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showRatingPicker.toggle()
                        if !showRatingPicker { isReviewFocused = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if userRating != nil {
                            Image(systemName: "star.fill")
                                .font(.sapphoDetail)
                                .foregroundColor(.sapphoWarning)
                        } else {
                            Image(systemName: "star")
                                .font(.sapphoDetail)
                                .foregroundColor(.sapphoTextMuted)
                            Text("Rate")
                                .font(.sapphoCaption)
                                .foregroundColor(.sapphoTextMuted)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                userRating != nil ? Color.sapphoWarning.opacity(0.5) : Color.sapphoTextMuted.opacity(0.3),
                                lineWidth: 1
                            )
                    )
                }

                // Comment count bubble - tappable to show/hide reviews
                if reviewCount > 0 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showReviews.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showReviews ? "bubble.left.fill" : "bubble.left")
                                .font(.sapphoDetail)
                                .foregroundColor(showReviews ? .sapphoPrimary : .sapphoTextMuted)
                            Text("\(reviewCount)")
                                .font(.sapphoCaption)
                                .foregroundColor(showReviews ? .sapphoPrimary : .sapphoTextMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    showReviews ? Color.sapphoPrimary.opacity(0.5) : Color.sapphoTextMuted.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }

            // Expandable star picker + review input (open/close together)
            if showRatingPicker {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                if userRating == star {
                                    Task { await clearRating() }
                                } else {
                                    Task { await setRating(star) }
                                }
                            } label: {
                                Image(systemName: star <= (userRating ?? 0) ? "star.fill" : "star")
                                    .font(.sapphoIconLarge)
                                    .foregroundColor(star <= (userRating ?? 0) ? .sapphoWarning : .sapphoTextMuted.opacity(0.4))
                            }
                            .accessibilityLabel("Rate \(star) star\(star == 1 ? "" : "s")")
                        }
                    }

                    // Review input
                    TextField("Write a review (optional)", text: $userReviewText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.sapphoBody)
                        .foregroundColor(.sapphoTextHigh)
                        .focused($isReviewFocused)
                        .padding(12)
                        .background(Color.sapphoSurface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    HStack {
                        Spacer()
                        Button {
                            Task { await submitReview() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSubmittingReview {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                }
                                Text("Submit")
                                    .font(.sapphoCaption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.sapphoPrimary)
                            .cornerRadius(8)
                        }
                        .disabled(isSubmittingReview || userReviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(userReviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Reviews dropdown (toggled by comment bubble)
            if showReviews {
                VStack(spacing: 10) {
                    ForEach(allReviewsWithText) { item in
                        reviewCard(item)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
    }

    private var allReviewsWithText: [ReviewItem] {
        reviews.filter { item in
            guard let review = item.review, !review.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return true
        }
    }





    private func reviewCard(_ item: ReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.sapphoBody)
                        .foregroundColor(.sapphoTextMuted)
                    Text(item.displayName ?? item.username ?? "User")
                        .font(.sapphoCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sapphoTextHigh)
                }

                Spacer()

                // Star rating
                if let rating = item.rating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.sapphoTiny)
                                .foregroundColor(star <= rating ? .sapphoWarning : .sapphoTextMuted)
                        }
                    }
                }
            }

            if let review = item.review {
                Text(review)
                    .font(.sapphoSmall)
                    .foregroundColor(.sapphoTextMedium)
            }

            if let dateString = item.updatedAt ?? item.createdAt {
                Text(relativeDate(from: dateString))
                    .font(.sapphoTiny)
                    .foregroundColor(.sapphoTextMuted)
            }
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(10)
    }

    private func relativeDate(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        var date = formatter.date(from: isoString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: isoString)
        }

        guard let parsedDate = date else { return "" }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .short
        return relativeFormatter.localizedString(for: parsedDate, relativeTo: Date())
    }

    // MARK: - Action Row (Download + Overflow + Play)
    private var actionRow: some View {
        HStack(spacing: 12) {
            // Download button
            Button {
                handleDownloadTap()
            } label: {
                downloadButtonLabel
            }
            .accessibilityLabel(downloadLabel)
            .accessibilityHint(downloadAccessibilityHint)

            // Edit button (admin only)
            if authRepository.isAdmin {
                Button {
                    showEditSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.sapphoDetail)
                        Text("Edit")
                            .font(.sapphoCaption)
                    }
                    .foregroundColor(.sapphoPrimary)
                    .frame(height: 60)
                    .padding(.horizontal, 12)
                    .background(Color.sapphoSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sapphoPrimary.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }
            }

            // Overflow menu button (icon only, 48x60)
            Button {
                showMoreMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.sapphoHeadline)
                    .foregroundColor(.sapphoTextHigh)
                    .frame(width: 48, height: 60)
                    .background(Color.sapphoSurface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(12)
            }
            .accessibilityLabel("More options")
            .accessibilityHint("Double tap to open menu with chapters, collections, and more")

            // Play/Continue button (expands to fill, on the right)
            Button {
                if isCurrentlyPlaying {
                    audioPlayer.togglePlayPause()
                } else {
                    Task {
                        await audioPlayer.play(audiobook: displayBook)
                        audioPlayer.showFullPlayer = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.sapphoIconMedium)
                    Text(isCurrentlyPlaying ? "Pause" : (hasProgress ? "Continue" : "Play"))
                        .font(.sapphoBodySemibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    isCurrentlyPlaying
                        ? Color.sapphoPlayingGreen.opacity(0.2)
                        : Color.sapphoPrimaryLight.opacity(0.2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .accessibilityLabel(isCurrentlyPlaying ? "Pause" : (hasProgress ? "Continue listening" : "Play"))
            .accessibilityHint(isCurrentlyPlaying ? "Double tap to pause playback" : "Double tap to start playing \(displayBook.title)")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Progress Section
    @ViewBuilder
    private var progressSection: some View {
        if let progress = displayBook.progress, let duration = displayBook.duration, duration > 0, (progress.position > 0 || progress.completed == 1) {
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
                    if !chapters.isEmpty {
                        let currentChapter = chapters.last { $0.startTime <= Double(progress.position) }
                        if let chapter = currentChapter {
                            let chapterIndex = chapters.firstIndex(where: { $0.startTime == chapter.startTime }) ?? 0
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill")
                                    .font(.sapphoIconMini)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(progressAccessibilityLabel(progress: progress, duration: duration))
            }
            .padding(.horizontal, 24)
        }
    }

    private func progressAccessibilityLabel(progress: Progress, duration: Int) -> String {
        if progress.completed == 1 {
            return "Progress: Completed"
        }
        var label = "Progress: \(formatDuration(progress.position)) listened of \(formatDuration(duration)) total, \(Int(progressPercent * 100)) percent"
        if !chapters.isEmpty {
            let currentChapter = chapters.last { $0.startTime <= Double(progress.position) }
            if let chapter = currentChapter {
                let chapterIndex = chapters.firstIndex(where: { $0.startTime == chapter.startTime }) ?? 0
                label += ", Chapter \(chapterIndex + 1) of \(chapters.count)"
            }
        }
        return label
    }

    // MARK: - Title and Metadata Section
    private var titleMetadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                // Header row with About title and Catch Up button (matches Android)
                HStack {
                    Text("About")
                        .font(.sapphoHeadline)
                        .foregroundColor(.sapphoTextHigh)
                    Spacer()
                    if catchUpVisible {
                        Button {
                            Task { await loadRecap() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14))
                                Text("Catch Up")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(Color(red: 0.655, green: 0.545, blue: 0.98)) // #A78BFA
                        }
                    }
                }

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
                .accessibilityLabel(descriptionExpanded ? "Show less of description" : "Show more of description")
                .accessibilityHint("Double tap to \(descriptionExpanded ? "collapse" : "expand") the description")

                // Recap content (inline below description)
                catchUpContent
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

    private func moreMenuItem(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.sapphoHeadlineMedium)
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.sapphoSubheadline)
                        .foregroundColor(.sapphoTextHigh)
                    Text(subtitle)
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoTextMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.sapphoCaptionSemibold)
                    .foregroundColor(.sapphoTextMuted.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sapphoBackground.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentAudiobook?.id == displayBook.id && audioPlayer.isPlaying
    }

    private var hasProgress: Bool {
        displayBook.progress?.position ?? 0 > 0
    }

    @ViewBuilder
    private var downloadButtonLabel: some View {
        switch downloadState {
        case .downloading(let progress):
            // Expanded button with progress bar
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.sapphoTextMuted)
                    Text("\(Int(progress * 100))%")
                        .font(.sapphoDetailSemibold)
                        .foregroundColor(.sapphoTextHigh)
                        .contentTransition(.numericText())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(Color.sapphoPrimary)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 100, height: 60)
            .background(Color.sapphoPrimary.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sapphoPrimary.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        default:
            downloadIconOnly
                .frame(width: 48, height: 60)
                .background(Color.sapphoSurface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var downloadIconOnly: some View {
        switch downloadState {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.sapphoIconSmall)
                .foregroundColor(.sapphoTextMuted)
        case .downloading:
            EmptyView()
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.sapphoIconSmall)
                .foregroundColor(.sapphoSuccess)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.sapphoIconSmall)
                .foregroundColor(.sapphoError)
        }
    }

    private var downloadLabel: String {
        switch downloadState {
        case .notDownloaded:
            return "Download"
        case .downloading(let progress):
            return "Downloading, \(Int(progress * 100)) percent"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Download failed"
        }
    }

    private var downloadAccessibilityHint: String {
        switch downloadState {
        case .notDownloaded:
            return "Double tap to download for offline listening"
        case .downloading:
            return "Double tap to cancel download"
        case .downloaded:
            return "Downloaded for offline listening"
        case .failed:
            return "Double tap to retry download"
        }
    }

    private func handleDownloadTap() {
        switch downloadState {
        case .notDownloaded, .failed:
            downloadManager.download(audiobook: displayBook)
        case .downloading:
            downloadManager.cancelDownload(audiobookId: displayBook.id)
        case .downloaded:
            // No-op: deletion only available from Downloads screen
            break
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
            async let bookRequest = api?.getAudiobook(id: audiobook.id)
            async let chaptersRequest = api?.getChapters(audiobookId: audiobook.id)
            fullAudiobook = try await bookRequest
            chapters = (try? await chaptersRequest) ?? []
            isFavorite = fullAudiobook?.isFavorite ?? false
            // Cache chapters for offline use
            if !chapters.isEmpty {
                DownloadManager.shared.cacheChapters(audiobookId: audiobook.id, chapters: chapters)
            }
        } catch {
            print("Failed to load audiobook: \(error)")
            // Fall back to cached metadata for offline
            let cached = DownloadManager.shared.cachedMeta[audiobook.id]
            if chapters.isEmpty, let cachedChapters = cached?.chapters {
                chapters = cachedChapters.map { $0.toChapter() }
            }
        }
        isLoading = false
    }

    private func toggleFavorite() async {
        do {
            let response = try await api?.toggleFavorite(audiobookId: displayBook.id)
            isFavorite = response?.isFavorite ?? isFavorite
            showToast(isFavorite ? "Added to reading list" : "Removed from reading list")
        } catch {
            showToast("Failed to update reading list")
        }
    }

    private func loadRating() async {
        do {
            let rating = try await api?.getUserRating(audiobookId: audiobook.id)
            userRating = rating?.rating
            userReviewText = rating?.review ?? ""
            averageRating = try await api?.getAverageRating(audiobookId: audiobook.id)
        } catch {
            print("Failed to load rating: \(error)")
        }
    }

    private func loadReviews() async {
        do {
            reviews = try await api?.getAllRatings(audiobookId: audiobook.id) ?? []
        } catch {
            print("Failed to load reviews: \(error)")
        }
    }

    private func submitReview() async {
        guard let currentRating = userRating else { return }
        isSubmittingReview = true
        isReviewFocused = false
        do {
            let reviewText = userReviewText.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await api?.setRating(
                audiobookId: displayBook.id,
                rating: currentRating,
                review: reviewText.isEmpty ? nil : reviewText
            )
            userRating = response?.rating
            userReviewText = response?.review ?? ""
            averageRating = try await api?.getAverageRating(audiobookId: displayBook.id)
            await loadReviews()
            showToast("Review submitted")
        } catch {
            showToast("Failed to submit review")
        }
        isSubmittingReview = false
    }

    private func setRating(_ rating: Int) async {
        do {
            let reviewText = userReviewText.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await api?.setRating(
                audiobookId: displayBook.id,
                rating: rating,
                review: reviewText.isEmpty ? nil : reviewText
            )
            userRating = response?.rating
            averageRating = try await api?.getAverageRating(audiobookId: displayBook.id)
            await loadReviews()
            showToast("Rated \(rating) star\(rating == 1 ? "" : "s")")
        } catch {
            showToast("Failed to set rating")
        }
    }

    private func clearRating() async {
        do {
            let _ = try await api?.setRating(audiobookId: displayBook.id, rating: nil)
            userRating = nil
            averageRating = try await api?.getAverageRating(audiobookId: displayBook.id)
            showToast("Rating cleared")
        } catch {
            showToast("Failed to clear rating")
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
            showToast("Marked as finished")
        } catch {
            showToast("Failed to mark finished")
        }
    }

    private func clearProgress() async {
        do {
            try await api?.clearProgress(audiobookId: displayBook.id)
            await loadFullAudiobook()
            showToast("Progress cleared")
        } catch {
            showToast("Failed to clear progress")
        }
    }

    // MARK: - Admin Actions

    private func refreshMetadata() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let refreshed = try await api?.refreshMetadata(audiobookId: displayBook.id)
            if let refreshed = refreshed {
                fullAudiobook = refreshed
                chapters = try await api?.getChapters(audiobookId: refreshed.id) ?? []
            }
            showToast("Metadata refreshed")
        } catch {
            showToast("Failed to refresh metadata")
        }
    }

    private func convertToM4B() async {
        isConverting = true
        defer { isConverting = false }
        do {
            let _ = try await api?.convertToM4B(audiobookId: displayBook.id)
            // Poll for completion
            while isConverting {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let status = try await api?.getConversionStatus(audiobookId: displayBook.id)
                if status?.status == "completed" {
                    fullAudiobook = try await api?.getAudiobook(id: displayBook.id)
                    showToast("Conversion complete")
                    return
                } else if status?.status == "failed" {
                    showToast("Conversion failed: \(status?.error ?? "unknown")")
                    return
                }
            }
        } catch {
            showToast("Failed to start conversion")
        }
    }

    // MARK: - Catch Up (AI Recap)

    private var catchUpVisible: Bool {
        let bookProgress = (fullAudiobook ?? audiobook).progress
        let bookHasProgress = (bookProgress?.position ?? 0 > 0) || (bookProgress?.completed ?? 0 == 1)
        return isAiConfigured && displayBook.series != nil && (bookHasProgress || previousBookCompleted)
    }

    @ViewBuilder
    private var catchUpContent: some View {
        if isLoadingRecap {
            VStack(spacing: 8) {
                ProgressView()
                    .tint(.sapphoTextMuted)
                Text("Generating recap...")
                    .font(.sapphoCaption)
                    .foregroundColor(.sapphoTextMuted)
                Text("This may take a moment")
                    .font(.sapphoCaption)
                    .foregroundColor(.sapphoTextMuted)
            }
            .padding()
        }

        if let error = recapError {
            VStack(spacing: 8) {
                Text(error)
                    .font(.sapphoCaption)
                    .foregroundColor(.red)
                Button("Retry") {
                    Task { await loadRecap() }
                }
                .font(.sapphoCaption)
                .foregroundColor(.sapphoPrimary)
            }
        }

        if let recap = recapText {
            VStack(alignment: .leading, spacing: 12) {
                Text(recap)
                    .font(.sapphoBody)
                    .foregroundColor(.sapphoTextHigh)
                    .textSelection(.enabled)

                HStack {
                    Spacer()
                    Button {
                        Task { await regenerateRecap() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Regenerate")
                        }
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoTextMuted)
                    }
                }
            }
            .padding(16)
            .background(Color.sapphoSurface)
            .cornerRadius(12)
        }
    }

    private func checkAiStatus() async {
        do {
            let status = try await api?.getAiStatus()
            isAiConfigured = status?.configured ?? false
        } catch {
            // AI not available, button stays hidden
        }
    }

    private func checkPreviousBookStatus() async {
        guard displayBook.series != nil else { return }
        do {
            let status = try await api?.getPreviousBookStatus(audiobookId: displayBook.id)
            previousBookCompleted = status?.previousBookCompleted ?? false
        } catch {
            // Ignore errors, button visibility falls back to progress check
        }
    }

    private func loadRecap() async {
        isLoadingRecap = true
        recapError = nil
        do {
            let response = try await api?.getAudiobookRecap(audiobookId: displayBook.id)
            recapText = response?.recap
        } catch {
            recapError = "Failed to generate recap. Please try again."
        }
        isLoadingRecap = false
    }

    private func regenerateRecap() async {
        recapText = nil
        do {
            try await api?.clearAudiobookRecap(audiobookId: displayBook.id)
        } catch {
            // Ignore clear error, try to regenerate anyway
        }
        await loadRecap()
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
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
                        .font(.sapphoSubheadline)
                        .foregroundColor(.sapphoPrimary)
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .font(.sapphoSubheadline)
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
                                            .font(.sapphoIconMini)
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
