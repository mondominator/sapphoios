import SwiftUI

struct EditMetadataSheet: View {
    @Environment(\.sapphoAPI) private var api
    @Environment(\.dismiss) private var dismiss

    let audiobook: Audiobook
    var onSave: (Audiobook) -> Void

    // MARK: - Form Fields
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var author: String = ""
    @State private var narrator: String = ""
    @State private var series: String = ""
    @State private var seriesPosition: String = ""
    @State private var genre: String = ""
    @State private var tags: String = ""
    @State private var language: String = ""
    @State private var abridged: Bool = false
    @State private var publisher: String = ""
    @State private var publishedYear: String = ""
    @State private var copyrightYear: String = ""
    @State private var isbn: String = ""
    @State private var asin: String = ""
    @State private var coverUrl: String = ""
    @State private var descriptionText: String = ""

    // MARK: - Search State
    @State private var searchResults: [MetadataSearchResult] = []
    @State private var isSearching = false
    @State private var showSearchResults = false

    // MARK: - Operation State
    @State private var isSaving = false
    @State private var isSavingAndEmbedding = false
    @State private var isFetchingChapters = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sapphoBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        searchSection
                        basicInfoSection
                        seriesSection
                        classificationSection
                        publishingSection
                        identifiersSection
                        coverSection
                        descriptionSection
                        actionButtons
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sapphoSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.sapphoPrimary)
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            populateFields()
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Search")

            Button {
                Task { await searchMetadata() }
            } label: {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Search Metadata")
                        .font(.sapphoBodySemibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.sapphoPrimary)
                .cornerRadius(10)
            }
            .disabled(isSearching)

            if showSearchResults {
                if searchResults.isEmpty && !isSearching {
                    Text("No results found")
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            Button {
                                applySearchResult(result)
                            } label: {
                                searchResultRow(result)
                            }
                            .buttonStyle(.plain)

                            if result.id != searchResults.last?.id {
                                Divider()
                                    .background(Color.sapphoBorder)
                            }
                        }
                    }
                    .background(Color.sapphoSurface)
                    .cornerRadius(10)
                }
            }
        }
    }

    private func searchResultRow(_ result: MetadataSearchResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title ?? "Unknown Title")
                    .font(.sapphoBodyMedium)
                    .foregroundColor(.sapphoTextHigh)
                    .lineLimit(2)

                if let resultAuthor = result.author, !resultAuthor.isEmpty {
                    Text(resultAuthor)
                        .font(.sapphoCaption)
                        .foregroundColor(.sapphoTextMuted)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let source = result.source {
                        Text(source)
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoPrimary)
                    }
                    if result.hasChapters == true {
                        Label("Chapters", systemImage: "list.bullet")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoSuccess)
                    }
                    if let resultAsin = result.asin, !resultAsin.isEmpty {
                        Text("ASIN: \(resultAsin)")
                            .font(.sapphoSmall)
                            .foregroundColor(.sapphoTextMuted)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.sapphoCaption)
                .foregroundColor(.sapphoTextMuted)
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Basic Info")

            metadataField("Title", text: $title)
            metadataField("Subtitle", text: $subtitle)
            metadataField("Author", text: $author)
            metadataField("Narrator", text: $narrator)
        }
    }

    // MARK: - Series Section

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Series")

            metadataField("Series Name", text: $series)
            metadataField("Series Position", text: $seriesPosition, keyboard: .decimalPad)
        }
    }

    // MARK: - Classification Section

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Classification")

            metadataField("Genre", text: $genre)
            metadataField("Tags", text: $tags)
            metadataField("Language", text: $language)

            Toggle(isOn: $abridged) {
                Text("Abridged")
                    .font(.sapphoBody)
                    .foregroundColor(.sapphoTextHigh)
            }
            .tint(.sapphoPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sapphoSurface)
            .cornerRadius(10)
        }
    }

    // MARK: - Publishing Section

    private var publishingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Publishing")

            metadataField("Publisher", text: $publisher)
            metadataField("Published Year", text: $publishedYear, keyboard: .numberPad)
            metadataField("Copyright Year", text: $copyrightYear, keyboard: .numberPad)
        }
    }

    // MARK: - Identifiers Section

    private var identifiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Identifiers")

            metadataField("ISBN", text: $isbn)

            HStack(spacing: 8) {
                metadataField("ASIN", text: $asin)

                Button {
                    Task { await fetchChapters() }
                } label: {
                    Group {
                        if isFetchingChapters {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "list.bullet.rectangle")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(asin.trimmingCharacters(in: .whitespaces).isEmpty ? Color.sapphoDisabled : Color.sapphoPrimary)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(asin.trimmingCharacters(in: .whitespaces).isEmpty || isFetchingChapters)
            }
        }
    }

    // MARK: - Cover Section

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Cover")

            metadataField("Cover Image URL", text: $coverUrl, keyboard: .URL)
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Description")

            TextEditor(text: $descriptionText)
                .font(.sapphoBody)
                .foregroundColor(.sapphoTextHigh)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120)
                .background(Color.sapphoSurface)
                .cornerRadius(10)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await save(embed: false) }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text("Save")
                        .font(.sapphoBodySemibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sapphoPrimary)
                .cornerRadius(10)
            }
            .disabled(isSaving || isSavingAndEmbedding)

            Button {
                Task { await save(embed: true) }
            } label: {
                HStack(spacing: 8) {
                    if isSavingAndEmbedding {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text("Save & Embed")
                        .font(.sapphoBodySemibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sapphoWarning)
                .cornerRadius(10)
            }
            .disabled(isSaving || isSavingAndEmbedding)
        }
        .padding(.top, 8)
    }

    // MARK: - Shared Components

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.sapphoTextMuted)
            .tracking(0.8)
    }

    private func metadataField(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.sapphoBody)
            .foregroundColor(.sapphoTextHigh)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .padding(12)
            .background(Color.sapphoSurface)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.sapphoBorder.opacity(0.3), lineWidth: 1)
            )
    }

    // MARK: - Populate Fields

    private func populateFields() {
        title = audiobook.title
        subtitle = audiobook.subtitle ?? ""
        author = audiobook.author ?? ""
        narrator = audiobook.narrator ?? ""
        series = audiobook.series ?? ""
        if let pos = audiobook.seriesPosition {
            seriesPosition = pos.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(pos))
                : String(pos)
        }
        genre = audiobook.genre ?? ""
        tags = audiobook.tags ?? ""
        language = audiobook.language ?? ""
        abridged = (audiobook.abridged ?? 0) == 1
        publisher = audiobook.publisher ?? ""
        if let year = audiobook.publishYear { publishedYear = String(year) }
        if let year = audiobook.copyrightYear { copyrightYear = String(year) }
        isbn = audiobook.isbn ?? ""
        asin = audiobook.asin ?? ""
        coverUrl = audiobook.coverImage ?? ""
        descriptionText = audiobook.description ?? ""
    }

    // MARK: - Apply Search Result

    private func applySearchResult(_ result: MetadataSearchResult) {
        if let v = result.title, !v.isEmpty { title = v }
        if let v = result.subtitle, !v.isEmpty { subtitle = v }
        if let v = result.author, !v.isEmpty { author = v }
        if let v = result.narrator, !v.isEmpty { narrator = v }
        if let v = result.description, !v.isEmpty { descriptionText = v }
        if let v = result.genre, !v.isEmpty { genre = v }
        if let v = result.series, !v.isEmpty { series = v }
        if let pos = result.seriesPosition {
            seriesPosition = pos.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(pos))
                : String(pos)
        }
        if let v = result.publishedYear { publishedYear = String(v) }
        if let v = result.publisher, !v.isEmpty { publisher = v }
        if let v = result.isbn, !v.isEmpty { isbn = v }
        if let v = result.asin, !v.isEmpty { asin = v }
        if let v = result.language, !v.isEmpty { language = v }
        if let v = result.image, !v.isEmpty { coverUrl = v }

        withAnimation { showSearchResults = false }
    }

    // MARK: - Search Metadata

    private func searchMetadata() async {
        isSearching = true
        showSearchResults = true

        do {
            let searchTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
            let searchAuthor = author.trimmingCharacters(in: .whitespaces).isEmpty ? nil : author
            searchResults = try await api?.searchMetadata(
                audiobookId: audiobook.id,
                title: searchTitle,
                author: searchAuthor
            ) ?? []
        } catch {
            searchResults = []
            showAlertMessage(title: "Search Failed", message: error.localizedDescription)
        }

        isSearching = false
    }

    // MARK: - Fetch Chapters

    private func fetchChapters() async {
        let trimmedAsin = asin.trimmingCharacters(in: .whitespaces)
        guard !trimmedAsin.isEmpty else { return }

        isFetchingChapters = true

        do {
            let response = try await api?.fetchChapters(audiobookId: audiobook.id, asin: trimmedAsin)
            let count = response?.chapterCount ?? 0
            showAlertMessage(
                title: "Chapters Fetched",
                message: response?.message ?? "Fetched \(count) chapter\(count == 1 ? "" : "s")."
            )
        } catch {
            showAlertMessage(title: "Fetch Failed", message: error.localizedDescription)
        }

        isFetchingChapters = false
    }

    // MARK: - Save

    private func save(embed: Bool) async {
        if embed {
            isSavingAndEmbedding = true
        } else {
            isSaving = true
        }

        do {
            let update = buildUpdateRequest()
            let updated = try await api?.updateAudiobook(id: audiobook.id, update: update)

            if embed {
                let embedResponse = try await api?.embedMetadata(audiobookId: audiobook.id)
                // Embedding succeeded — dismiss after callback
                if let book = updated {
                    onSave(book)
                }
                isSavingAndEmbedding = false
                showAlertMessage(
                    title: "Embedded",
                    message: embedResponse?.message ?? "Metadata embedded into file."
                )
                // Dismiss after a short delay so user sees the alert
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } else {
                if let book = updated {
                    onSave(book)
                }
                isSaving = false
                dismiss()
            }
        } catch {
            isSaving = false
            isSavingAndEmbedding = false
            showAlertMessage(title: "Save Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Build Update Request

    private func buildUpdateRequest() -> AudiobookUpdateRequest {
        var update = AudiobookUpdateRequest()

        update.title = title.trimmingCharacters(in: .whitespaces)
        update.subtitle = subtitle.trimmingCharacters(in: .whitespaces).isEmpty ? nil : subtitle.trimmingCharacters(in: .whitespaces)
        update.author = author.trimmingCharacters(in: .whitespaces).isEmpty ? nil : author.trimmingCharacters(in: .whitespaces)
        update.narrator = narrator.trimmingCharacters(in: .whitespaces).isEmpty ? nil : narrator.trimmingCharacters(in: .whitespaces)
        update.description = descriptionText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : descriptionText.trimmingCharacters(in: .whitespaces)
        update.genre = genre.trimmingCharacters(in: .whitespaces).isEmpty ? nil : genre.trimmingCharacters(in: .whitespaces)
        update.tags = tags.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tags.trimmingCharacters(in: .whitespaces)
        update.series = series.trimmingCharacters(in: .whitespaces).isEmpty ? nil : series.trimmingCharacters(in: .whitespaces)
        update.seriesPosition = Float(seriesPosition.trimmingCharacters(in: .whitespaces))
        update.publishedYear = Int(publishedYear.trimmingCharacters(in: .whitespaces))
        update.copyrightYear = Int(copyrightYear.trimmingCharacters(in: .whitespaces))
        update.publisher = publisher.trimmingCharacters(in: .whitespaces).isEmpty ? nil : publisher.trimmingCharacters(in: .whitespaces)
        update.isbn = isbn.trimmingCharacters(in: .whitespaces).isEmpty ? nil : isbn.trimmingCharacters(in: .whitespaces)
        update.asin = asin.trimmingCharacters(in: .whitespaces).isEmpty ? nil : asin.trimmingCharacters(in: .whitespaces)
        update.language = language.trimmingCharacters(in: .whitespaces).isEmpty ? nil : language.trimmingCharacters(in: .whitespaces)
        update.abridged = abridged
        update.coverUrl = coverUrl.trimmingCharacters(in: .whitespaces).isEmpty ? nil : coverUrl.trimmingCharacters(in: .whitespaces)

        return update
    }

    // MARK: - Alert Helper

    private func showAlertMessage(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

#Preview {
    EditMetadataSheet(
        audiobook: Audiobook(
            id: 1,
            title: "The Great Gatsby",
            subtitle: nil,
            author: "F. Scott Fitzgerald",
            narrator: "Jake Gyllenhaal",
            series: nil,
            seriesPosition: nil,
            duration: 36000,
            genre: "Fiction",
            tags: "classic, american",
            publishYear: 1925,
            copyrightYear: nil,
            publisher: "Scribner",
            isbn: "978-0743273565",
            asin: "B0EXAMPLE",
            language: "English",
            rating: nil,
            userRating: nil,
            averageRating: nil,
            abridged: 0,
            description: "The story of the mysteriously wealthy Jay Gatsby and his love for the beautiful Daisy Buchanan.",
            coverImage: nil,
            fileCount: 1,
            isMultiFile: nil,
            createdAt: "",
            progress: nil,
            chapters: nil,
            isFavorite: false
        ),
        onSave: { _ in }
    )
}
