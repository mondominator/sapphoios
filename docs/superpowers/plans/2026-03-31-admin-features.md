# iOS Admin Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add all admin features to iOS audiobook detail screen matching Android: edit metadata, refresh metadata, delete audiobook, convert to M4B, embed metadata, fetch chapters, edit chapter titles, metadata search.

**Architecture:** Add API endpoints to SapphoAPI.swift, request/response models to Models.swift, then build the UI in AudiobookDetailView.swift with a new EditMetadataSheet.swift for the edit dialog. All admin features gated behind `authRepository.isAdmin`.

**Tech Stack:** SwiftUI, async/await, @Observable, @Environment

---

### Task 1: Add API Endpoints and Models

**Files:**
- Modify: `Sappho/Data/Remote/SapphoAPI.swift`
- Modify: `Sappho/Domain/Model/Models.swift`

Add all missing admin API endpoints and request/response models.

**Models to add in Models.swift:**

- [ ] **Step 1: Add AudiobookUpdateRequest model**

```swift
struct AudiobookUpdateRequest: Codable {
    var title: String?
    var subtitle: String?
    var author: String?
    var narrator: String?
    var description: String?
    var genre: String?
    var tags: String?
    var series: String?
    var seriesPosition: Float?
    var publishedYear: Int?
    var copyrightYear: Int?
    var publisher: String?
    var isbn: String?
    var asin: String?
    var language: String?
    var rating: Float?
    var abridged: Bool?
    var coverUrl: String?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, author, narrator, description, genre, tags
        case series, publisher, isbn, asin, language, rating, abridged
        case seriesPosition = "series_position"
        case publishedYear = "published_year"
        case copyrightYear = "copyright_year"
        case coverUrl = "cover_url"
    }
}
```

- [ ] **Step 2: Add MetadataSearchResult model**

```swift
struct MetadataSearchResult: Codable, Identifiable {
    var id: String { asin ?? title ?? UUID().uuidString }
    let title: String?
    let subtitle: String?
    let author: String?
    let narrator: String?
    let description: String?
    let genre: String?
    let series: String?
    let seriesPosition: Float?
    let publishedYear: Int?
    let publisher: String?
    let isbn: String?
    let asin: String?
    let language: String?
    let image: String?
    let source: String?
    let hasChapters: Bool?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, author, narrator, description, genre
        case series, publisher, isbn, asin, language, image, source
        case seriesPosition = "series_position"
        case publishedYear = "published_year"
        case hasChapters = "has_chapters"
    }
}

struct MetadataSearchResponse: Codable {
    let results: [MetadataSearchResult]
}
```

- [ ] **Step 3: Add remaining request/response models**

```swift
struct FetchChaptersRequest: Codable {
    let asin: String
}

struct FetchChaptersResponse: Codable {
    let message: String
    let chapterCount: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case chapterCount = "chapterCount"
    }
}

struct ChapterUpdate: Codable {
    let id: Int
    let title: String
}

struct ChapterUpdateRequest: Codable {
    let chapters: [ChapterUpdate]
}

struct EmbedMetadataResponse: Codable {
    let message: String
    let backup: String?
}

struct ConvertResponse: Codable {
    let jobId: String?
    let status: String?
    let error: String?
}

struct ConversionStatusResponse: Codable {
    let status: String?
    let progress: Int?
    let message: String?
    let error: String?
}
```

- [ ] **Step 4: Add API endpoints to SapphoAPI.swift**

```swift
// Admin - Metadata
func updateAudiobook(id: Int, request: AudiobookUpdateRequest) async throws -> Audiobook {
    try await requestJSON("api/audiobooks/\(id)", method: "PUT", body: request)
}

func refreshMetadata(audiobookId: Int) async throws -> Audiobook {
    let response: RefreshMetadataResponse = try await requestJSON("api/audiobooks/\(audiobookId)/refresh-metadata", method: "POST")
    return response.audiobook
}

func searchMetadata(audiobookId: Int, title: String?, author: String?, asin: String? = nil) async throws -> [MetadataSearchResult] {
    var params: [String: String] = [:]
    if let title = title { params["title"] = title }
    if let author = author { params["author"] = author }
    if let asin = asin { params["asin"] = asin }
    let query = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
    let response: MetadataSearchResponse = try await requestJSON("api/audiobooks/\(audiobookId)/search-audnexus?\(query)")
    return response.results
}

func embedMetadata(audiobookId: Int) async throws -> EmbedMetadataResponse {
    try await requestJSON("api/audiobooks/\(audiobookId)/embed-metadata", method: "POST")
}

func fetchChapters(audiobookId: Int, asin: String) async throws -> FetchChaptersResponse {
    let body = FetchChaptersRequest(asin: asin)
    return try await requestJSON("api/audiobooks/\(audiobookId)/fetch-chapters", method: "POST", body: body)
}

func updateChapters(audiobookId: Int, chapters: [ChapterUpdate]) async throws {
    let body = ChapterUpdateRequest(chapters: chapters)
    try await requestVoid("api/audiobooks/\(audiobookId)/chapters", method: "PUT", body: body)
}

func deleteAudiobook(id: Int) async throws {
    try await requestVoid("api/audiobooks/\(id)", method: "DELETE")
}

func convertToM4B(audiobookId: Int) async throws -> ConvertResponse {
    try await requestJSON("api/audiobooks/\(audiobookId)/convert-to-m4b", method: "POST")
}

func getConversionStatus(audiobookId: Int) async throws -> ConversionStatusResponse {
    try await requestJSON("api/audiobooks/\(audiobookId)/conversion-status")
}
```

Also add a helper struct:
```swift
struct RefreshMetadataResponse: Codable {
    let message: String
    let audiobook: Audiobook
}
```

- [ ] **Step 5: Build and verify compilation**

Run: `xcodebuild -scheme Sappho -destination 'generic/platform=iOS' build`

- [ ] **Step 6: Commit**

```
feat: add admin API endpoints and models for metadata management
```

---

### Task 2: Add Admin Menu Items to Detail View

**Files:**
- Modify: `Sappho/Presentation/Detail/AudiobookDetailView.swift`

Add Edit button, overflow menu items (refresh, convert, delete), and state variables for all admin operations.

- [ ] **Step 1: Add state variables for admin operations**

Near existing state variables (around line 34), add:
```swift
@State private var showEditSheet = false
@State private var showDeleteConfirm = false
@State private var isRefreshing = false
@State private var isConverting = false
@State private var conversionProgress: Int = 0
@State private var showChapterEditor = false
```

- [ ] **Step 2: Add Edit button next to overflow menu button**

In the button row area (near the overflow "..." button), add an Edit button visible only to admins:
```swift
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sapphoPrimary.opacity(0.3), lineWidth: 1)
        )
    }
}
```

- [ ] **Step 3: Add admin overflow menu items**

After the existing Clear Progress item in the more menu, add admin-only items:
```swift
if authRepository.isAdmin {
    Divider().background(Color.sapphoTextMuted.opacity(0.3))

    // Refresh Metadata
    Button { ... } label: {
        Label("Refresh Metadata", systemImage: "arrow.clockwise")
    }

    // Convert to M4B (conditional)
    if let filePath = displayBook.filePath,
       !filePath.hasSuffix(".m4b") || displayBook.isMultiFile == 1 {
        Button { ... } label: {
            Label("Convert to M4B", systemImage: "arrow.triangle.swap")
        }
    }

    // Edit Chapters
    if !chapters.isEmpty {
        Button { ... } label: {
            Label("Edit Chapters", systemImage: "list.bullet.indent")
        }
    }

    Divider().background(Color.sapphoTextMuted.opacity(0.3))

    // Delete Audiobook (destructive)
    Button(role: .destructive) { ... } label: {
        Label("Delete Audiobook", systemImage: "trash")
    }
}
```

- [ ] **Step 4: Add delete confirmation alert**

```swift
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
```

- [ ] **Step 5: Add refresh metadata action**

```swift
private func refreshMetadata() async {
    isRefreshing = true
    defer { isRefreshing = false }
    do {
        let refreshed = try await api?.refreshMetadata(audiobookId: displayBook.id)
        if let refreshed = refreshed {
            fullAudiobook = refreshed
        }
        showToast("Metadata refreshed")
    } catch {
        showToast("Failed to refresh metadata")
    }
}
```

- [ ] **Step 6: Add convert to M4B action with polling**

```swift
private func convertToM4B() async {
    isConverting = true
    defer { isConverting = false; conversionProgress = 0 }
    do {
        let response = try await api?.convertToM4B(audiobookId: displayBook.id)
        // Poll status
        while isConverting {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let status = try await api?.getConversionStatus(audiobookId: displayBook.id)
            conversionProgress = status?.progress ?? 0
            if status?.status == "completed" {
                showToast("Conversion complete")
                // Reload audiobook
                fullAudiobook = try await api?.getAudiobook(id: displayBook.id)
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
```

- [ ] **Step 7: Add sheet for edit metadata**

```swift
.sheet(isPresented: $showEditSheet) {
    if let book = fullAudiobook ?? audiobook as? Audiobook {
        EditMetadataSheet(audiobook: book) { updatedBook in
            fullAudiobook = updatedBook
        }
    }
}
```

- [ ] **Step 8: Build and verify**

Run: `xcodebuild -scheme Sappho -destination 'generic/platform=iOS' build`

- [ ] **Step 9: Commit**

```
feat: add admin buttons and actions to audiobook detail view
```

---

### Task 3: Create Edit Metadata Sheet

**Files:**
- Create: `Sappho/Presentation/Detail/EditMetadataSheet.swift`

Full metadata editor matching Android's EditMetadataDialog with search, fetch chapters, and embed.

- [ ] **Step 1: Create EditMetadataSheet.swift**

The sheet should have:
- All editable fields grouped in sections (Basic Info, Series, Classification, Publishing, Identifiers, Cover, Description)
- Search button that searches AudNexus/Google/OpenLibrary
- Search results list with tap-to-apply
- Fetch Chapters button (requires ASIN)
- Save button
- Save & Embed button
- Cancel/dismiss

Key state:
```swift
@State private var title: String
@State private var subtitle: String
@State private var author: String
@State private var narrator: String
@State private var series: String
@State private var seriesPosition: String
@State private var genre: String
@State private var tags: String
@State private var publishedYear: String
@State private var copyrightYear: String
@State private var publisher: String
@State private var isbn: String
@State private var asin: String
@State private var language: String
@State private var description: String
@State private var coverUrl: String
@State private var abridged: Bool

// Operation states
@State private var isSaving = false
@State private var isSearching = false
@State private var isEmbedding = false
@State private var isFetchingChapters = false
@State private var searchResults: [MetadataSearchResult] = []
@State private var showSearchResults = false
@State private var toastMessage: String?
```

Form sections matching Android layout, using SwiftUI Form/Section pattern.

- [ ] **Step 2: Implement search and apply functionality**

Search button calls `api.searchMetadata()`, results shown in a list. Tapping a result populates the form fields.

- [ ] **Step 3: Implement save, save & embed, fetch chapters**

Three action buttons:
- Save: builds `AudiobookUpdateRequest`, calls `api.updateAudiobook()`
- Save & Embed: saves first, then calls `api.embedMetadata()`
- Fetch Chapters: calls `api.fetchChapters()` with ASIN field value

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme Sappho -destination 'generic/platform=iOS' build`

- [ ] **Step 5: Commit**

```
feat: add edit metadata sheet with search, embed, and fetch chapters
```

---

### Task 4: Add Edit Chapter Titles

**Files:**
- Create: `Sappho/Presentation/Detail/EditChaptersSheet.swift`
- Modify: `Sappho/Presentation/Detail/AudiobookDetailView.swift`

- [ ] **Step 1: Create EditChaptersSheet.swift**

Sheet with list of chapters, each with editable title TextField. Save button calls `api.updateChapters()`.

- [ ] **Step 2: Wire up in AudiobookDetailView**

Add `.sheet(isPresented: $showChapterEditor)` presenting EditChaptersSheet.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```
feat: add chapter title editing for admin users
```

---

### Task 5: Add to project.yml and final integration test

**Files:**
- Modify: `project.yml` (add new Swift files to sources)

- [ ] **Step 1: Verify all new files are included in build**

- [ ] **Step 2: Full build test**

Run: `xcodebuild -scheme Sappho -destination 'generic/platform=iOS' build`

- [ ] **Step 3: Commit all and push**

```
feat: iOS admin features - edit, refresh, delete, convert, embed, chapters
```
