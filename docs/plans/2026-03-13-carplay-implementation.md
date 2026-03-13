# CarPlay Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add CarPlay audio app support to Sappho, allowing users to browse their library, control playback, and navigate chapters from their car's infotainment system.

**Architecture:** CarPlay runs as a separate scene in the same process as the phone app. Both scenes share the same `AudioPlayerService`, `SapphoAPI`, and `AuthRepository` instances — no IPC needed. Uses the modern scene-based approach (`CPTemplateApplicationSceneDelegate`), required for new CarPlay audio apps (iOS 14+).

**Tech Stack:** CarPlay framework, CPTemplateApplicationSceneDelegate, CPTabBarTemplate, CPListTemplate, CPNowPlayingTemplate, Swift/SwiftUI environment

---

### Task 1: Add CarPlay Entitlement

**Files:**
- Modify: `/Users/mondo/Documents/git/sapphoios/Sappho/Resources/Sappho.entitlements`

**Step 1: Add the CarPlay audio entitlement**

Open `Sappho.entitlements` and add the `com.apple.developer.carplay-audio` boolean entitlement:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.sappho.audiobooks</string>
    </array>
    <key>com.apple.developer.carplay-audio</key>
    <true/>
</dict>
</plist>
```

**Step 2: Verify entitlements**

Run: `cat /Users/mondo/Documents/git/sapphoios/Sappho/Resources/Sappho.entitlements`
Expected: Both `application-groups` and `carplay-audio` keys present.

**Step 3: Commit**

```bash
git add Sappho/Resources/Sappho.entitlements
git commit -m "feat(carplay): add CarPlay audio entitlement"
```

---

### Task 2: Add CarPlay Scene Configuration to Info.plist

**Files:**
- Modify: `/Users/mondo/Documents/git/sapphoios/Sappho/Resources/Info.plist`

**Step 1: Add CarPlay scene to UIApplicationSceneManifest**

Replace the existing `UIApplicationSceneManifest` section and add the CarPlay scene configuration. The key changes:
- Set `UIApplicationSupportsMultipleScenes` to `true` (required for CarPlay + phone to coexist)
- Add `UISceneConfigurations` with both the default phone scene and the CarPlay scene

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneConfigurationName</key>
                <string>CarPlay</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
    </dict>
</dict>
```

**Important:** We do NOT need a `UIWindowSceneSessionRoleApplication` entry because `SapphoApp.swift` uses the `@main` SwiftUI app lifecycle, which handles the default window scene automatically. Only the CarPlay scene needs an explicit configuration.

**Step 2: Build to verify plist is valid**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Sappho/Resources/Info.plist
git commit -m "feat(carplay): add CarPlay scene configuration to Info.plist"
```

---

### Task 3: Create CarPlaySceneDelegate (Minimal Skeleton)

**Files:**
- Create: `/Users/mondo/Documents/git/sapphoios/Sappho/CarPlay/CarPlaySceneDelegate.swift`
- Modify: `Sappho.xcodeproj/project.pbxproj` (add file to build)

**Step 1: Create the CarPlay directory**

```bash
mkdir -p /Users/mondo/Documents/git/sapphoios/Sappho/CarPlay
```

**Step 2: Write the minimal CarPlaySceneDelegate**

This is the entry point. On connect, it receives a `CPInterfaceController` and builds the tab bar. For now, just show a single empty tab to verify the wiring works.

```swift
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let placeholder = CPListTemplate(
            title: "Sappho",
            sections: [
                CPListSection(items: [
                    CPListItem(text: "Loading…", detailText: nil)
                ])
            ]
        )

        let tabBar = CPTabBarTemplate(templates: [placeholder])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }
}
```

**Step 3: Add file to Xcode project**

The file must be added to `project.pbxproj`. Use the ruby helper or add manually through Xcode. The file reference needs to be in:
1. `PBXBuildFile` section (for compilation)
2. `PBXFileReference` section
3. `PBXGroup` section (under a new "CarPlay" group)
4. `PBXSourcesBuildPhase` section

Since manual pbxproj editing is fragile, use this approach:

```bash
cd /Users/mondo/Documents/git/sapphoios
# Use xcodebuild to verify the file compiles — but first we need it in the project.
# The safest approach is to use the ruby xcodeproj gem or add via Xcode.
# For scripted addition, we'll use a python script.
python3 -c "
import subprocess
import re

pbxproj_path = 'Sappho.xcodeproj/project.pbxproj'
with open(pbxproj_path, 'r') as f:
    content = f.read()

# Check if already added
if 'CarPlaySceneDelegate.swift' in content:
    print('Already in project')
    exit(0)

import uuid
import hashlib

def generate_uuid(name):
    h = hashlib.md5(name.encode()).hexdigest().upper()
    return h[:24]

file_ref_id = generate_uuid('CarPlaySceneDelegate.swift_ref')
build_file_id = generate_uuid('CarPlaySceneDelegate.swift_build')
group_id = generate_uuid('CarPlay_group')

# We need to find the Sappho group and add a CarPlay subgroup
# This is complex - let's just print the IDs for manual addition
print(f'File ref: {file_ref_id}')
print(f'Build file: {build_file_id}')
print(f'Group: {group_id}')
"
```

**Alternative (recommended):** Open `Sappho.xcodeproj` in Xcode, right-click the `Sappho` folder in the navigator, select "New Group" → "CarPlay", then drag `CarPlaySceneDelegate.swift` into it. Or use the `add-swift-file` helper pattern from previous tasks.

For CI/scripted addition, the pbxproj entries follow the same pattern as existing files. Look at how `AudioPlayerService.swift` is referenced and replicate for `CarPlaySceneDelegate.swift` with path `Sappho/CarPlay/CarPlaySceneDelegate.swift`.

**Step 4: Build to verify**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add Sappho/CarPlay/CarPlaySceneDelegate.swift Sappho.xcodeproj/project.pbxproj
git commit -m "feat(carplay): add CarPlaySceneDelegate skeleton"
```

---

### Task 4: Create CarPlayContentProvider

**Files:**
- Create: `/Users/mondo/Documents/git/sapphoios/Sappho/CarPlay/CarPlayContentProvider.swift`
- Create: `/Users/mondo/Documents/git/sapphoios/SapphoTests/CarPlayContentProviderTests.swift`
- Modify: `Sappho.xcodeproj/project.pbxproj`

This is the data layer that fetches content from `SapphoAPI` and builds `CPListItem` arrays. It's the most testable component.

**Step 1: Write tests for CarPlayContentProvider**

```swift
import XCTest
@testable import Sappho

final class CarPlayContentProviderTests: XCTestCase {

    // MARK: - List Item Building

    func testBuildListItemFromAudiobook() {
        let book = Audiobook(
            id: 1,
            title: "Test Book",
            subtitle: nil,
            author: "Test Author",
            narrator: nil,
            series: "Test Series",
            seriesPosition: 2,
            seriesIndex: nil,
            duration: 3600,
            genre: nil,
            normalizedGenre: nil,
            tags: nil,
            publishYear: nil,
            copyrightYear: nil,
            publisher: nil,
            isbn: nil,
            asin: nil,
            language: nil,
            rating: nil,
            userRating: nil,
            averageRating: nil,
            abridged: nil,
            description: nil,
            coverImage: nil,
            fileCount: 1,
            isMultiFile: nil,
            createdAt: "2024-01-01",
            progress: nil,
            chapters: nil,
            isFavorite: false,
            isQueued: nil,
            lastPlayed: nil
        )

        let item = CarPlayContentProvider.listItem(for: book)
        XCTAssertEqual(item.text, "Test Book")
        XCTAssertEqual(item.detailText, "Test Author · 1h 0m")
    }

    func testBuildListItemWithProgress() {
        let progress = Progress(
            id: 1,
            userId: 1,
            audiobookId: 1,
            position: 1800,
            completed: 0,
            lastListened: nil,
            updatedAt: nil,
            currentChapter: nil
        )
        let book = Audiobook(
            id: 1,
            title: "Half Done",
            subtitle: nil,
            author: "Author",
            narrator: nil,
            series: nil,
            seriesPosition: nil,
            seriesIndex: nil,
            duration: 3600,
            genre: nil,
            normalizedGenre: nil,
            tags: nil,
            publishYear: nil,
            copyrightYear: nil,
            publisher: nil,
            isbn: nil,
            asin: nil,
            language: nil,
            rating: nil,
            userRating: nil,
            averageRating: nil,
            abridged: nil,
            description: nil,
            coverImage: nil,
            fileCount: 1,
            isMultiFile: nil,
            createdAt: "2024-01-01",
            progress: progress,
            chapters: nil,
            isFavorite: false,
            isQueued: nil,
            lastPlayed: nil
        )

        let item = CarPlayContentProvider.listItem(for: book)
        XCTAssertEqual(item.detailText, "Author · 50%")
    }

    func testFormatDurationHoursAndMinutes() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(7260), "2h 1m")
        XCTAssertEqual(CarPlayContentProvider.formatDuration(3600), "1h 0m")
        XCTAssertEqual(CarPlayContentProvider.formatDuration(1800), "30m")
        XCTAssertEqual(CarPlayContentProvider.formatDuration(45), "1m")
    }

    func testBuildCategoryItems() {
        let authors = [
            AuthorInfo(name: "Author A", bookCount: 5),
            AuthorInfo(name: "Author B", bookCount: 3)
        ]

        let items = CarPlayContentProvider.categoryItems(from: authors)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].text, "Author A")
        XCTAssertEqual(items[0].detailText, "5 books")
        XCTAssertEqual(items[1].text, "Author B")
        XCTAssertEqual(items[1].detailText, "3 books")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild test -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SapphoTests/CarPlayContentProviderTests 2>&1 | tail -10`
Expected: FAIL — `CarPlayContentProvider` not defined.

**Step 3: Implement CarPlayContentProvider**

```swift
import CarPlay

/// Provides content for CarPlay templates by fetching data from SapphoAPI
/// and building CPListItem/CPListSection arrays.
final class CarPlayContentProvider {

    private let api: SapphoAPI
    private let audioPlayer: AudioPlayerService

    init(api: SapphoAPI, audioPlayer: AudioPlayerService) {
        self.api = api
        self.audioPlayer = audioPlayer
    }

    // MARK: - Home Tab

    /// Builds home sections: Continue Listening, Up Next, Recently Added, Listen Again
    func homeTemplate(onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        async let inProgress = api.getInProgress(limit: 10)
        async let upNext = api.getUpNext(limit: 10)
        async let recent = api.getRecentlyAdded(limit: 10)
        async let finished = api.getFinished(limit: 10)

        var sections: [CPListSection] = []

        if let books = try? await inProgress, !books.isEmpty {
            let items = books.map { book in
                let item = Self.listItem(for: book)
                item.handler = { _, completion in
                    onSelect(book)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Continue Listening", sectionIndexTitle: nil))
        }

        if let books = try? await upNext, !books.isEmpty {
            let items = books.map { book in
                let item = Self.listItem(for: book)
                item.handler = { _, completion in
                    onSelect(book)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Up Next", sectionIndexTitle: nil))
        }

        if let books = try? await recent, !books.isEmpty {
            let items = books.map { book in
                let item = Self.listItem(for: book)
                item.handler = { _, completion in
                    onSelect(book)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Recently Added", sectionIndexTitle: nil))
        }

        if let books = try? await finished, !books.isEmpty {
            let items = books.map { book in
                let item = Self.listItem(for: book)
                item.handler = { _, completion in
                    onSelect(book)
                    completion()
                }
                return item
            }
            sections.append(CPListSection(items: items, header: "Listen Again", sectionIndexTitle: nil))
        }

        if sections.isEmpty {
            sections.append(CPListSection(items: [
                CPListItem(text: "No audiobooks yet", detailText: "Add books from the Sappho web app")
            ]))
        }

        let template = CPListTemplate(title: "Home", sections: sections)
        template.tabSystemItem = .mostRecent
        return template
    }

    // MARK: - Library Tab

    /// Builds the library root with Authors, Series, Collections, All Books categories.
    func libraryTemplate(
        onAuthors: @escaping () -> Void,
        onSeries: @escaping () -> Void,
        onCollections: @escaping () -> Void,
        onAllBooks: @escaping () -> Void
    ) -> CPListTemplate {
        let authorsItem = CPListItem(text: "Authors", detailText: nil, image: UIImage(systemName: "person.2.fill"))
        authorsItem.accessoryType = .disclosureIndicator
        authorsItem.handler = { _, completion in
            onAuthors()
            completion()
        }

        let seriesItem = CPListItem(text: "Series", detailText: nil, image: UIImage(systemName: "books.vertical.fill"))
        seriesItem.accessoryType = .disclosureIndicator
        seriesItem.handler = { _, completion in
            onSeries()
            completion()
        }

        let collectionsItem = CPListItem(text: "Collections", detailText: nil, image: UIImage(systemName: "folder.fill"))
        collectionsItem.accessoryType = .disclosureIndicator
        collectionsItem.handler = { _, completion in
            onCollections()
            completion()
        }

        let allBooksItem = CPListItem(text: "All Books", detailText: nil, image: UIImage(systemName: "book.fill"))
        allBooksItem.accessoryType = .disclosureIndicator
        allBooksItem.handler = { _, completion in
            onAllBooks()
            completion()
        }

        let template = CPListTemplate(title: "Library", sections: [
            CPListSection(items: [authorsItem, seriesItem, collectionsItem, allBooksItem])
        ])
        template.tabSystemItem = .search
        return template
    }

    /// Builds author list from API.
    func authorsListTemplate(onSelect: @escaping (String) -> Void) async -> CPListTemplate {
        let authors = (try? await api.getAuthors()) ?? []
        let items = authors.prefix(100).map { author in
            let item = CPListItem(
                text: author.name,
                detailText: "\(author.bookCount) \(author.bookCount == 1 ? "book" : "books")"
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { _, completion in
                onSelect(author.name)
                completion()
            }
            return item
        }

        return CPListTemplate(title: "Authors", sections: [CPListSection(items: items)])
    }

    /// Builds series list from API.
    func seriesListTemplate(onSelect: @escaping (String) -> Void) async -> CPListTemplate {
        let series = (try? await api.getSeries()) ?? []
        let items = series.prefix(100).map { s in
            let item = CPListItem(
                text: s.name,
                detailText: "\(s.bookCount) \(s.bookCount == 1 ? "book" : "books")"
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { _, completion in
                onSelect(s.name)
                completion()
            }
            return item
        }

        return CPListTemplate(title: "Series", sections: [CPListSection(items: items)])
    }

    /// Builds collection list from API.
    func collectionsListTemplate(onSelect: @escaping (Collection) -> Void) async -> CPListTemplate {
        let collections = (try? await api.getCollections()) ?? []
        let items = collections.prefix(100).map { collection in
            let item = CPListItem(
                text: collection.name,
                detailText: "\(collection.bookCount ?? 0) \(collection.bookCount == 1 ? "book" : "books")"
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { _, completion in
                onSelect(collection)
                completion()
            }
            return item
        }

        return CPListTemplate(title: "Collections", sections: [CPListSection(items: items)])
    }

    /// Builds book list for a given author.
    func booksForAuthor(_ author: String, onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        let books = (try? await api.getByAuthor(author)) ?? []
        let items = books.prefix(100).map { book in
            let item = Self.listItem(for: book)
            item.handler = { _, completion in
                onSelect(book)
                completion()
            }
            return item
        }

        return CPListTemplate(title: author, sections: [CPListSection(items: items)])
    }

    /// Builds book list for a given series.
    func booksForSeries(_ series: String, onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        let books = (try? await api.getBySeries(series)) ?? []
        let sortedBooks = books.sorted { ($0.seriesPosition ?? 0) < ($1.seriesPosition ?? 0) }
        let items = sortedBooks.prefix(100).map { book in
            let item = Self.listItem(for: book)
            if let pos = book.seriesPosition {
                let posStr = pos.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", pos)
                    : String(format: "%.1f", pos)
                item.detailText = "#\(posStr) · \(book.author ?? "")"
            }
            item.handler = { _, completion in
                onSelect(book)
                completion()
            }
            return item as CPListItem
        }

        return CPListTemplate(title: series, sections: [CPListSection(items: items)])
    }

    /// Builds book list for a given collection.
    func booksForCollection(_ collection: Collection, onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        let detail = try? await api.getCollection(id: collection.id)
        let books = detail?.books ?? []
        let items = books.prefix(100).map { book in
            let item = Self.listItem(for: book)
            item.handler = { _, completion in
                onSelect(book)
                completion()
            }
            return item
        }

        return CPListTemplate(title: collection.name, sections: [CPListSection(items: items)])
    }

    /// Builds all books list.
    func allBooksTemplate(onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        let books = (try? await api.getAudiobooks()) ?? []
        let items = books.prefix(100).map { book in
            let item = Self.listItem(for: book)
            item.handler = { _, completion in
                onSelect(book)
                completion()
            }
            return item
        }

        return CPListTemplate(title: "All Books", sections: [CPListSection(items: items)])
    }

    // MARK: - Reading List Tab

    /// Builds the reading list (favorites) template.
    func readingListTemplate(onSelect: @escaping (Audiobook) -> Void) async -> CPListTemplate {
        let books = (try? await api.getFavorites(sort: "custom")) ?? []
        let items = books.enumerated().map { index, book in
            let item = Self.listItem(for: book)
            // Prepend position number
            item.text = "\(index + 1). \(book.title)"
            item.handler = { _, completion in
                onSelect(book)
                completion()
            }
            return item as CPListItem
        }

        let section = items.isEmpty
            ? CPListSection(items: [CPListItem(text: "No books in reading list", detailText: "Add books from the app")])
            : CPListSection(items: items)

        let template = CPListTemplate(title: "Reading List", sections: [section])
        template.tabSystemItem = .favorites
        return template
    }

    // MARK: - Static Helpers

    /// Builds a CPListItem from an Audiobook model.
    static func listItem(for book: Audiobook) -> CPListItem {
        let detail: String
        if let progress = book.progress, !progress.isCompleted,
           let duration = book.duration, duration > 0 {
            let percent = Int(Double(progress.position) / Double(duration) * 100)
            detail = "\(book.author ?? "Unknown") · \(percent)%"
        } else if let duration = book.duration {
            detail = "\(book.author ?? "Unknown") · \(formatDuration(duration))"
        } else {
            detail = book.author ?? "Unknown"
        }

        let item = CPListItem(text: book.title, detailText: detail)
        return item
    }

    /// Builds category items from AuthorInfo array (also usable for SeriesInfo).
    static func categoryItems(from authors: [AuthorInfo]) -> [CPListItem] {
        authors.map { author in
            CPListItem(
                text: author.name,
                detailText: "\(author.bookCount) \(author.bookCount == 1 ? "book" : "books")"
            )
        }
    }

    /// Formats duration in seconds to "Xh Ym" or "Ym" string.
    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild test -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SapphoTests/CarPlayContentProviderTests 2>&1 | tail -10`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add Sappho/CarPlay/CarPlayContentProvider.swift SapphoTests/CarPlayContentProviderTests.swift Sappho.xcodeproj/project.pbxproj
git commit -m "feat(carplay): add CarPlayContentProvider with tests"
```

---

### Task 5: Create CarPlayNowPlayingManager

**Files:**
- Create: `/Users/mondo/Documents/git/sapphoios/Sappho/CarPlay/CarPlayNowPlayingManager.swift`
- Modify: `Sappho.xcodeproj/project.pbxproj`

**Step 1: Implement CarPlayNowPlayingManager**

This class configures the `CPNowPlayingTemplate` with custom buttons for chapter navigation and speed control. Artwork and standard controls (play/pause, progress) are auto-populated from `MPNowPlayingInfoCenter`, which `AudioPlayerService` already manages.

```swift
import CarPlay

/// Configures the CPNowPlayingTemplate with custom buttons for
/// chapter navigation and playback speed cycling.
final class CarPlayNowPlayingManager {

    private let audioPlayer: AudioPlayerService
    private let nowPlayingTemplate: CPNowPlayingTemplate

    /// Speed options to cycle through.
    private let speedOptions: [Float] = [1.0, 1.25, 1.5, 2.0]

    init(audioPlayer: AudioPlayerService) {
        self.audioPlayer = audioPlayer
        self.nowPlayingTemplate = CPNowPlayingTemplate.shared
        configureButtons()
    }

    var template: CPNowPlayingTemplate {
        nowPlayingTemplate
    }

    // MARK: - Configuration

    private func configureButtons() {
        let chapterBackButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "backward.end.fill")!
        ) { [weak self] _ in
            self?.previousChapter()
        }

        let chapterForwardButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "forward.end.fill")!
        ) { [weak self] _ in
            self?.nextChapter()
        }

        let speedButton = CPNowPlayingImageButton(
            image: UIImage(systemName: "gauge.with.needle.fill")!
        ) { [weak self] _ in
            self?.cycleSpeed()
        }

        nowPlayingTemplate.updateNowPlayingButtons([
            chapterBackButton,
            chapterForwardButton,
            speedButton
        ])

        nowPlayingTemplate.isUpNextButtonEnabled = false
        nowPlayingTemplate.isAlbumArtistButtonEnabled = false
    }

    // MARK: - Actions

    private func previousChapter() {
        guard let chapters = audioPlayer.currentAudiobook?.chapters,
              let current = audioPlayer.currentChapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else { return }

        let prev = chapters[currentIndex - 1]
        audioPlayer.jumpToChapter(prev)
    }

    private func nextChapter() {
        guard let chapters = audioPlayer.currentAudiobook?.chapters,
              let current = audioPlayer.currentChapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == current.id }),
              currentIndex < chapters.count - 1 else { return }

        let next = chapters[currentIndex + 1]
        audioPlayer.jumpToChapter(next)
    }

    private func cycleSpeed() {
        let currentSpeed = audioPlayer.playbackSpeed
        // Find next speed in the cycle
        if let currentIndex = speedOptions.firstIndex(of: currentSpeed) {
            let nextIndex = (currentIndex + 1) % speedOptions.count
            audioPlayer.setPlaybackSpeed(speedOptions[nextIndex])
        } else {
            // If current speed isn't in our list, reset to 1x
            audioPlayer.setPlaybackSpeed(1.0)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Sappho/CarPlay/CarPlayNowPlayingManager.swift Sappho.xcodeproj/project.pbxproj
git commit -m "feat(carplay): add CarPlayNowPlayingManager with chapter nav and speed control"
```

---

### Task 6: Wire Up Full CarPlaySceneDelegate

**Files:**
- Modify: `/Users/mondo/Documents/git/sapphoios/Sappho/CarPlay/CarPlaySceneDelegate.swift`

**Step 1: Replace the skeleton with the full implementation**

The delegate needs to access the shared `AudioPlayerService` and `SapphoAPI` instances. Since CarPlay runs in the same process, we access the shared instances from the SwiftUI app's environment. The cleanest way is to store them as static properties on `SapphoApp` or use the existing singleton pattern.

First, check how services are accessed. In `SapphoApp.swift`, the services are created as `@State` properties. We need a way for CarPlaySceneDelegate to access them. The simplest approach: store references in a shared container.

Add a simple service locator that SapphoApp populates on launch:

```swift
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var contentProvider: CarPlayContentProvider?
    private var nowPlayingManager: CarPlayNowPlayingManager?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        guard let api = ServiceLocator.shared.api,
              let audioPlayer = ServiceLocator.shared.audioPlayer else {
            let errorTemplate = CPListTemplate(
                title: "Sappho",
                sections: [CPListSection(items: [
                    CPListItem(text: "Not signed in", detailText: "Open Sappho on your phone to sign in")
                ])]
            )
            interfaceController.setRootTemplate(errorTemplate, animated: false, completion: nil)
            return
        }

        contentProvider = CarPlayContentProvider(api: api, audioPlayer: audioPlayer)
        nowPlayingManager = CarPlayNowPlayingManager(audioPlayer: audioPlayer)

        Task {
            await buildAndSetRootTemplate(audioPlayer: audioPlayer)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.contentProvider = nil
        self.nowPlayingManager = nil
    }

    // MARK: - Template Building

    private func buildAndSetRootTemplate(audioPlayer: AudioPlayerService) async {
        guard let contentProvider, let nowPlayingManager, let interfaceController else { return }

        let onSelect: (Audiobook) -> Void = { [weak self] book in
            self?.playBook(book, audioPlayer: audioPlayer)
        }

        // Build tabs concurrently
        async let homeTab = contentProvider.homeTemplate(onSelect: onSelect)
        let libraryTab = contentProvider.libraryTemplate(
            onAuthors: { [weak self] in self?.showAuthors(audioPlayer: audioPlayer) },
            onSeries: { [weak self] in self?.showSeries(audioPlayer: audioPlayer) },
            onCollections: { [weak self] in self?.showCollections(audioPlayer: audioPlayer) },
            onAllBooks: { [weak self] in self?.showAllBooks(audioPlayer: audioPlayer) }
        )
        async let readingListTab = contentProvider.readingListTemplate(onSelect: onSelect)
        let nowPlayingTab = nowPlayingManager.template

        let tabBar = CPTabBarTemplate(templates: [
            await homeTab,
            libraryTab,
            await readingListTab,
            nowPlayingTab
        ])

        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    // MARK: - Navigation Handlers

    private func playBook(_ book: Audiobook, audioPlayer: AudioPlayerService) {
        Task {
            await audioPlayer.play(audiobook: book)
        }
        // Navigate to Now Playing
        if let tabBar = interfaceController?.rootTemplate as? CPTabBarTemplate {
            // Now Playing is the last tab
            let nowPlayingIndex = tabBar.templates.count - 1
            tabBar.selectTemplate(at: nowPlayingIndex)
        }
    }

    private func showAuthors(audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.authorsListTemplate { [weak self] author in
                self?.showBooksForAuthor(author, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showBooksForAuthor(_ author: String, audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.booksForAuthor(author) { [weak self] book in
                self?.playBook(book, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showSeries(audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.seriesListTemplate { [weak self] series in
                self?.showBooksForSeries(series, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showBooksForSeries(_ series: String, audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.booksForSeries(series) { [weak self] book in
                self?.playBook(book, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showCollections(audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.collectionsListTemplate { [weak self] collection in
                self?.showBooksForCollection(collection, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showBooksForCollection(_ collection: Collection, audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.booksForCollection(collection) { [weak self] book in
                self?.playBook(book, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showAllBooks(audioPlayer: AudioPlayerService) {
        guard let contentProvider else { return }
        Task {
            let template = await contentProvider.allBooksTemplate { [weak self] book in
                self?.playBook(book, audioPlayer: audioPlayer)
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Sappho/CarPlay/CarPlaySceneDelegate.swift
git commit -m "feat(carplay): wire up full tab bar with home, library, reading list, now playing"
```

---

### Task 7: Create ServiceLocator and Wire Into SapphoApp

**Files:**
- Create: `/Users/mondo/Documents/git/sapphoios/Sappho/App/ServiceLocator.swift`
- Modify: `/Users/mondo/Documents/git/sapphoios/Sappho/App/SapphoApp.swift`
- Modify: `Sappho.xcodeproj/project.pbxproj`

**Step 1: Create ServiceLocator**

A simple shared container that `SapphoApp` populates on launch and `CarPlaySceneDelegate` reads from.

```swift
import Foundation

/// Lightweight service locator that allows CarPlay (which runs as a separate scene
/// in the same process) to access the shared service instances created by SapphoApp.
final class ServiceLocator {
    static let shared = ServiceLocator()

    var api: SapphoAPI?
    var audioPlayer: AudioPlayerService?
    var authRepository: AuthRepository?

    private init() {}
}
```

**Step 2: Populate ServiceLocator in SapphoApp**

In `SapphoApp.swift`, after creating the services, store them in `ServiceLocator`. Add these lines inside the `init()` or at the point where services are configured:

```swift
// Inside SapphoApp, after creating api and audioPlayer:
ServiceLocator.shared.api = api
ServiceLocator.shared.audioPlayer = audioPlayer
ServiceLocator.shared.authRepository = authRepository
```

If `SapphoApp` uses `@State` for these (which means they're set up in `body` or `init`), add the ServiceLocator population in the `.onAppear` or `init` block where the services are first available.

**Step 3: Build and verify**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Sappho/App/ServiceLocator.swift Sappho/App/SapphoApp.swift Sappho.xcodeproj/project.pbxproj
git commit -m "feat(carplay): add ServiceLocator for shared service access across scenes"
```

---

### Task 8: Add Cover Art Thumbnails to CarPlay List Items

**Files:**
- Modify: `/Users/mondo/Documents/git/sapphoios/Sappho/CarPlay/CarPlayContentProvider.swift`

**Step 1: Add thumbnail loading to list items**

CarPlay recommends 90x90 thumbnails. We can load them asynchronously after building the list items, using the existing `ImageCache` or `URLSession`.

Add a method to `CarPlayContentProvider` that loads and attaches cover thumbnails:

```swift
// Add to CarPlayContentProvider

/// Loads a cover thumbnail for a CarPlay list item.
/// CarPlay recommends 90x90 images.
private func loadThumbnail(for bookId: Int, into item: CPListItem) {
    guard let url = api.coverURL(for: bookId) else { return }

    // Check memory/disk cache first
    if let cached = ImageCache.shared.image(for: url.absoluteString) {
        let thumbnail = Self.resizedImage(cached, to: CGSize(width: 90, height: 90))
        item.setImage(thumbnail)
        return
    }

    // Load asynchronously
    Task {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }

        // Cache for future use
        ImageCache.shared.store(image, for: url.absoluteString)

        let thumbnail = Self.resizedImage(image, to: CGSize(width: 90, height: 90))
        await MainActor.run {
            item.setImage(thumbnail)
        }
    }
}

/// Resizes an image to the target size for CarPlay thumbnails.
static func resizedImage(_ image: UIImage, to size: CGSize) -> UIImage {
    UIGraphicsImageRenderer(size: size).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
}
```

Then update `listItem(for:)` to be an instance method (or add a separate method) that calls `loadThumbnail` after building each item. Update all call sites in `homeTemplate`, `booksForAuthor`, etc. to call `loadThumbnail(for: book.id, into: item)` after creating each item.

**Step 2: Build to verify**

Run: `cd /Users/mondo/Documents/git/sapphoios && xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Sappho/CarPlay/CarPlayContentProvider.swift
git commit -m "feat(carplay): add cover art thumbnails to list items"
```

---

### Task 9: Handle Authentication State Changes

**Files:**
- Modify: `/Users/mondo/Documents/git/sapphoios/Sappho/CarPlay/CarPlaySceneDelegate.swift`

**Step 1: Add auth state observation**

If the user logs out while CarPlay is connected, show a "Not signed in" screen. If they log in, rebuild the templates.

```swift
// Add to CarPlaySceneDelegate

private var authObservation: NSObjectProtocol?

// In didConnect, after setting up templates:
private func observeAuthChanges() {
    // Poll auth state periodically or observe via NotificationCenter
    // For simplicity, we can check on each template interaction
    // Or post a notification from AuthRepository on login/logout
}
```

For a lightweight approach, `CarPlaySceneDelegate` can check `ServiceLocator.shared.authRepository?.isAuthenticated` before each API call. If not authenticated, show the "Not signed in" template.

This is a nice-to-have refinement. The core implementation in Tasks 1-8 handles the main case where the user is already authenticated when CarPlay connects.

**Step 2: Commit**

```bash
git add Sappho/CarPlay/CarPlaySceneDelegate.swift
git commit -m "feat(carplay): handle unauthenticated state gracefully"
```

---

### Task 10: Test with CarPlay Simulator

**Step 1: Build and run**

```bash
cd /Users/mondo/Documents/git/sapphoios
xcodebuild -project Sappho.xcodeproj -scheme Sappho -destination 'id=00008101-000955A61A8B001E' -derivedDataPath build
```

**Step 2: Test with CarPlay Simulator**

1. Open Xcode → Window → Devices and Simulators
2. Or use the CarPlay Simulator app (included with Xcode additional tools)
3. In the iOS Simulator: Features → CarPlay → Show CarPlay Screen
4. The Sappho app should appear in the CarPlay dashboard

**Step 3: Verify functionality**

- [ ] Home tab shows sections (Continue Listening, Up Next, Recently Added, Listen Again)
- [ ] Library tab shows Authors, Series, Collections, All Books
- [ ] Tapping an author drills into their books
- [ ] Tapping a series drills into books sorted by position
- [ ] Tapping a collection drills into its books
- [ ] All Books shows the full library
- [ ] Reading List shows favorited books in order
- [ ] Tapping any book starts playback and navigates to Now Playing
- [ ] Now Playing shows current track info and artwork
- [ ] Chapter back/forward buttons work
- [ ] Speed button cycles through 1x → 1.25x → 1.5x → 2x → 1x
- [ ] Play/pause controls work
- [ ] Cover art thumbnails load on list items
- [ ] "Not signed in" shows if unauthenticated

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(carplay): complete CarPlay audio app support"
```

---

## Summary

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Entitlements | Add `com.apple.developer.carplay-audio` |
| 2 | Info.plist | Add CarPlay scene configuration |
| 3 | CarPlaySceneDelegate | Minimal skeleton with placeholder tab |
| 4 | CarPlayContentProvider | Data fetching + CPListItem building (with tests) |
| 5 | CarPlayNowPlayingManager | Now Playing with chapter nav + speed control |
| 6 | CarPlaySceneDelegate | Full tab bar wiring |
| 7 | ServiceLocator | Shared service access for CarPlay scene |
| 8 | Thumbnails | Cover art on list items |
| 9 | Auth handling | Graceful unauthenticated state |
| 10 | Testing | CarPlay Simulator verification |

**Total new files:** 4 (CarPlaySceneDelegate, CarPlayContentProvider, CarPlayNowPlayingManager, ServiceLocator)
**Modified files:** 3 (Sappho.entitlements, Info.plist, SapphoApp.swift) + project.pbxproj
**Test files:** 1 (CarPlayContentProviderTests)

**Note on Apple Developer Portal:** The `com.apple.developer.carplay-audio` entitlement requires approval from Apple. You must submit a CarPlay entitlement request at https://developer.apple.com/contact/carplay/ before the entitlement will work on real devices. It works in the CarPlay Simulator without approval.
