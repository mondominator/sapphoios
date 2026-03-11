import SwiftUI

struct ReadingListView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var upNext: [Audiobook] = []
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
            } else if upNext.isEmpty {
                EmptyStateView(
                    icon: "list.bullet",
                    title: "Nothing Up Next",
                    message: "Add audiobooks to your Up Next queue from the book detail page."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { index, audiobook in
                            NavigationLink {
                                AudiobookDetailView(audiobook: audiobook)
                            } label: {
                                UpNextRow(audiobook: audiobook, position: index + 1)
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
        .navigationTitle("Up Next")
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
        isLoading = upNext.isEmpty
        errorMessage = nil

        do {
            upNext = try await api?.getUpNext(limit: 50) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct UpNextRow: View {
    @Environment(\.sapphoAPI) private var api
    let audiobook: Audiobook
    let position: Int

    private var progressPercent: Double? {
        guard let progress = audiobook.progress,
              let duration = audiobook.duration,
              duration > 0 else { return nil }
        return Double(progress.position) / Double(duration)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Position number
            Text("\(position)")
                .font(.sapphoHeadline)
                .foregroundColor(.sapphoPrimary)
                .frame(width: 30)

            // Cover
            CoverImage(audiobookId: audiobook.id)
                .frame(width: 60, height: 85)
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
                    HStack(spacing: 4) {
                        Text(series)
                        if let pos = audiobook.seriesPosition {
                            Text("#\(formatSeriesPosition(pos))")
                        }
                    }
                    .font(.sapphoSmall)
                    .foregroundColor(.sapphoPrimary)
                    .lineLimit(1)
                }

                Spacer().frame(height: 4)

                // Duration
                if let duration = audiobook.duration {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatDuration(duration))
                            .font(.sapphoSmall)
                    }
                    .foregroundColor(.sapphoTextMuted)
                }

                // Progress bar if started
                if let percent = progressPercent, percent > 0 {
                    ProgressView(value: percent)
                        .tint(.sapphoPrimary)
                        .scaleEffect(y: 0.5)
                }
            }

            Spacer()

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

    private func formatSeriesPosition(_ position: Float) -> String {
        if position == floor(position) {
            return String(format: "%.0f", position)
        }
        return String(format: "%.1f", position)
    }
}

#Preview {
    NavigationStack {
        ReadingListView()
    }
    .environment(AuthRepository())
}
