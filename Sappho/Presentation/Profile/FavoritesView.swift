import SwiftUI

struct FavoritesView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var favorites: [Audiobook] = []
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
            } else if favorites.isEmpty {
                EmptyStateView(
                    icon: "heart",
                    title: "No Favorites",
                    message: "Tap the heart icon on any audiobook to add it to your favorites."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(favorites) { audiobook in
                            NavigationLink {
                                AudiobookDetailView(audiobook: audiobook)
                            } label: {
                                FavoriteBookRow(audiobook: audiobook)
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
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = favorites.isEmpty
        errorMessage = nil

        do {
            favorites = try await api?.getFavorites() ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct FavoriteBookRow: View {
    @Environment(\.sapphoAPI) private var api
    let audiobook: Audiobook

    private var progressPercent: Double? {
        guard let progress = audiobook.progress,
              let duration = audiobook.duration,
              duration > 0 else { return nil }
        return Double(progress.position) / Double(duration)
    }

    private var isCompleted: Bool {
        audiobook.progress?.completed == 1
    }

    var body: some View {
        HStack(spacing: 12) {
            // Cover
            CoverImage(audiobookId: audiobook.id)
                .frame(width: 70, height: 100)
                .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(audiobook.title)
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(2)

                if let author = audiobook.author {
                    Text(author)
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoTextMuted)
                        .lineLimit(1)
                }

                if let series = audiobook.series {
                    Text(series)
                        .font(.sapphoSmall)
                        .foregroundColor(.sapphoPrimary)
                        .lineLimit(1)
                }

                Spacer().frame(height: 4)

                // Duration and progress
                HStack(spacing: 12) {
                    if let duration = audiobook.duration {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(formatDuration(duration))
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoTextMuted)
                    }

                    if isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Completed")
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoSuccess)
                    } else if let percent = progressPercent, percent > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 10))
                            Text("\(Int(percent * 100))%")
                                .font(.sapphoSmall)
                        }
                        .foregroundColor(.sapphoWarning)
                    }
                }

                // Progress bar
                if let percent = progressPercent, !isCompleted {
                    ProgressView(value: percent)
                        .tint(.sapphoPrimary)
                        .scaleEffect(y: 0.5)
                }
            }

            Spacer()

            // Heart icon
            Image(systemName: "heart.fill")
                .font(.system(size: 16))
                .foregroundColor(.sapphoError)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .background(Color.sapphoSurface)
        .cornerRadius(12)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
    }
    .environment(AuthRepository())
}
