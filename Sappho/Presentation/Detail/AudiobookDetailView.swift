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

    private var displayBook: Audiobook {
        fullAudiobook ?? audiobook
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Cover and Basic Info
                VStack(spacing: 16) {
                    // Cover Image
                    AsyncImage(url: api?.coverURL(for: displayBook.id)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.sapphoSurface)
                            .aspectRatio(0.7, contentMode: .fit)
                            .overlay(
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.sapphoTextMuted)
                            )
                    }
                    .frame(maxWidth: 250)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)

                    // Title
                    Text(displayBook.title)
                        .font(.sapphoTitle)
                        .foregroundColor(.sapphoTextHigh)
                        .multilineTextAlignment(.center)

                    // Author
                    if let author = displayBook.author {
                        Text("by \(author)")
                            .font(.sapphoSubheadline)
                            .foregroundColor(.sapphoTextMuted)
                    }

                    // Series info
                    if let series = displayBook.series {
                        HStack(spacing: 4) {
                            Text(series)
                            if let position = displayBook.seriesPosition {
                                Text("• Book \(Int(position))")
                            }
                        }
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoPrimary)
                    }
                }
                .padding(.top, 16)

                // Action Buttons
                HStack(spacing: 16) {
                    // Play Button
                    Button {
                        Task {
                            await audioPlayer.play(audiobook: displayBook)
                        }
                        showPlayer = true
                    } label: {
                        HStack {
                            Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                            Text(isCurrentlyPlaying ? "Pause" : (hasProgress ? "Continue" : "Play"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SapphoPrimaryButtonStyle())

                    // Favorite Button
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundColor(isFavorite ? .sapphoError : .sapphoTextMuted)
                    }
                    .frame(width: 50, height: 50)
                    .background(Color.sapphoSurface)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)

                // Progress
                if let progress = displayBook.progress, let duration = displayBook.duration, duration > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress.position), total: Double(duration))
                            .tint(.sapphoPrimary)

                        HStack {
                            Text(formatTime(progress.position))
                            Spacer()
                            Text(formatTime(duration - progress.position) + " left")
                        }
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                    }
                    .padding(.horizontal, 16)
                }

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    if let narrator = displayBook.narrator {
                        MetadataRow(label: "Narrator", value: narrator)
                    }

                    if let duration = displayBook.duration {
                        MetadataRow(label: "Duration", value: formatDuration(duration))
                    }

                    if let genre = displayBook.genre {
                        MetadataRow(label: "Genre", value: genre)
                    }

                    if let year = displayBook.publishYear {
                        MetadataRow(label: "Published", value: String(year))
                    }
                }
                .padding(16)
                .background(Color.sapphoSurface)
                .cornerRadius(12)
                .padding(.horizontal, 16)

                // Description
                if let description = displayBook.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.sapphoHeadline)
                            .foregroundColor(.sapphoTextHigh)

                        Text(description)
                            .font(.sapphoBody)
                            .foregroundColor(.sapphoTextMedium)
                            .lineLimit(nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                }

                // Chapters
                if let chapters = displayBook.chapters, !chapters.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Chapters")
                            .font(.sapphoHeadline)
                            .foregroundColor(.sapphoTextHigh)
                            .padding(.horizontal, 16)

                        ForEach(chapters) { chapter in
                            Button {
                                Task {
                                    await audioPlayer.play(audiobook: displayBook, startPosition: chapter.startTime)
                                }
                                showPlayer = true
                            } label: {
                                HStack {
                                    Text(chapter.title ?? "Chapter \(chapter.id)")
                                        .font(.sapphoBody)
                                        .foregroundColor(.sapphoTextHigh)
                                        .lineLimit(1)

                                    Spacer()

                                    if let duration = chapter.duration {
                                        Text(formatDuration(Int(duration)))
                                            .font(.sapphoCaption)
                                            .foregroundColor(.sapphoTextMuted)
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }

                            if chapter.id != chapters.last?.id {
                                Divider()
                                    .background(Color.sapphoSurface)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color.sapphoSurface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
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
        .task {
            await loadFullAudiobook()
        }
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.currentAudiobook?.id == displayBook.id && audioPlayer.isPlaying
    }

    private var hasProgress: Bool {
        displayBook.progress?.position ?? 0 > 0
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
