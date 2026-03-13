import SwiftUI

struct ReadingListView: View {
    @Environment(\.sapphoAPI) private var api
    @State private var books: [Audiobook] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sortOption: String = "custom"
    @State private var editMode: EditMode = .inactive

    private let sortOptions = [
        ("custom", "Custom"),
        ("title", "Title"),
        ("date_added", "Date Added")
    ]

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadData() }
                }
            } else if books.isEmpty {
                EmptyStateView(
                    icon: "list.bullet",
                    title: "Nothing Up Next",
                    message: "Add audiobooks to your reading list from the book detail page."
                )
            } else {
                VStack(spacing: 0) {
                    // Sort picker
                    HStack {
                        Text("Sort by")
                            .font(.sapphoCaption)
                            .foregroundColor(.sapphoTextMuted)

                        Picker("Sort", selection: $sortOption) {
                            ForEach(sortOptions, id: \.0) { option in
                                Text(option.1).tag(option.0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.sapphoPrimary)

                        Spacer()

                        if sortOption == "custom" {
                            Button(editMode == .active ? "Done" : "Reorder") {
                                withAnimation {
                                    editMode = editMode == .active ? .inactive : .active
                                }
                            }
                            .font(.sapphoSubheadline)
                            .foregroundColor(.sapphoPrimary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    List {
                        ForEach(Array(books.enumerated()), id: \.element.id) { index, audiobook in
                            NavigationLink {
                                AudiobookDetailView(audiobook: audiobook)
                            } label: {
                                ReadingListRow(audiobook: audiobook, position: index + 1)
                            }
                            .listRowBackground(Color.sapphoSurface)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await removeBook(audiobook) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: sortOption == "custom" ? moveBooks : nil)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 100, for: .scrollContent)
                    .environment(\.editMode, $editMode)
                }
            }
        }
        .background(Color.sapphoBackground)
        .navigationTitle("Reading List")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.sapphoBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .onChange(of: sortOption) { _, _ in
            editMode = .inactive
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = books.isEmpty
        errorMessage = nil

        do {
            books = try await api?.getFavorites(sort: sortOption) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func moveBooks(from source: IndexSet, to destination: Int) {
        books.move(fromOffsets: source, toOffset: destination)

        // Send new order to server
        let order = books.map { $0.id }
        Task {
            do {
                try await api?.reorderFavorites(order: order)
            } catch {
                print("Failed to reorder: \(error)")
                // Reload to restore server state
                await loadData()
            }
        }
    }

    private func removeBook(_ audiobook: Audiobook) async {
        // Optimistic removal
        withAnimation {
            books.removeAll { $0.id == audiobook.id }
        }

        do {
            try await api?.removeFavorite(audiobookId: audiobook.id)
        } catch {
            print("Failed to remove: \(error)")
            await loadData()
        }
    }
}

// MARK: - Reading List Row
struct ReadingListRow: View {
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.sapphoPrimary)
                .frame(width: 28)

            // Cover
            CoverImage(audiobookId: audiobook.id)
                .frame(width: 56, height: 56)
                .cornerRadius(6)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(audiobook.title)
                    .font(.sapphoSubheadline)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let author = audiobook.author {
                        Text(author)
                            .lineLimit(1)
                    }

                    if let duration = audiobook.duration {
                        Text("·")
                        Text(formatDuration(duration))
                    }
                }
                .font(.sapphoSmall)
                .foregroundColor(.sapphoTextMuted)

                // Progress bar if started
                if let percent = progressPercent, percent > 0 {
                    ProgressView(value: percent)
                        .tint(.sapphoPrimary)
                        .scaleEffect(y: 0.5)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

}

#Preview {
    NavigationStack {
        ReadingListView()
    }
    .environment(AuthRepository())
}
