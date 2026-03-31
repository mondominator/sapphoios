import SwiftUI

struct EditChaptersSheet: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss

    let audiobookId: Int
    let chapters: [Chapter]
    var onSave: () -> Void

    @State private var editedTitles: [Int: String] = [:]
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sapphoBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(chapters) { chapter in
                            HStack(spacing: 12) {
                                Text("\(chapter.chapterNumber)")
                                    .font(.sapphoCaption)
                                    .foregroundColor(.sapphoTextMuted)
                                    .frame(width: 30, alignment: .trailing)

                                TextField(
                                    "Chapter \(chapter.chapterNumber)",
                                    text: Binding(
                                        get: { editedTitles[chapter.id] ?? chapter.title ?? "Chapter \(chapter.chapterNumber)" },
                                        set: { editedTitles[chapter.id] = $0 }
                                    )
                                )
                                .font(.sapphoBody)
                                .foregroundColor(.sapphoTextHigh)
                                .padding(10)
                                .background(Color.sapphoSurface)
                                .cornerRadius(8)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Edit Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sapphoPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveChapters() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text("Save")
                        }
                    }
                    .foregroundColor(.sapphoPrimary)
                    .disabled(isSaving || editedTitles.isEmpty)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveChapters() async {
        guard !editedTitles.isEmpty else { return }
        isSaving = true

        let updates = editedTitles.map { ChapterUpdate(id: $0.key, title: $0.value) }

        do {
            try await api?.updateChapters(audiobookId: audiobookId, chapters: updates)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }
}
