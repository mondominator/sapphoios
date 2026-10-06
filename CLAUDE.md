# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Sappho iOS is a native Swift/SwiftUI iOS app for the Sappho audiobook server. It provides feature parity with the Android app (sapphoapp), including:

- Authentication with dynamic server URL
- Library browsing (all, series, authors, genres, collections)
- Audio playback with background audio support
- Progress sync with server
- Offline downloads
- AirPlay and CarPlay support
- Sleep timer, playback speed control
- Lock screen / Now Playing controls

**Tech Stack:**
- Swift 5.9+ / SwiftUI
- iOS 17.0+ minimum
- AVFoundation for audio playback
- URLSession for networking
- Keychain for token storage (server URL and user info live in UserDefaults by design)

## Build Commands

### Generate Xcode Project

```bash
# Generate/regenerate the Xcode project
xcodegen generate
```

### Building

```bash
# Build for simulator
xcodebuild -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for device (requires signing)
xcodebuild -scheme Sappho -destination 'generic/platform=iOS' build
```

### Running on Device/Simulator

Open `Sappho.xcodeproj` in Xcode and press Run, or:

```bash
# Run on simulator
xcodebuild -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl boot "iPhone 17"
xcrun simctl install booted build/Debug-iphonesimulator/Sappho.app
xcrun simctl launch booted com.sappho.audiobook
```

Note: the bundle id is `com.sappho.audiobook` (singular) — it is the shipped
App Store id and immutable.

### Testing

```bash
# Run unit tests
xcodebuild test -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Architecture Overview

### Project Structure

```
Sappho/
├── App/                    # App entry point, AppDelegate, RootView, ServiceLocator
├── CarPlay/               # CarPlay scene delegate, content provider
├── Data/
│   ├── Remote/            # SapphoAPI (URLSession)
│   └── Repository/        # AuthRepository (Keychain + UserDefaults)
├── Domain/Model/          # Data models (Audiobook, User, etc.)
├── Presentation/
│   ├── Login/
│   ├── Home/
│   ├── Library/
│   ├── Detail/
│   ├── Player/
│   ├── Search/
│   ├── Profile/
│   ├── Notifications/
│   └── Components/        # Shared UI, Theme, TimeFormatting
└── Service/
    ├── AudioPlayerService.swift
    ├── DownloadManager.swift
    └── NetworkMonitor.swift
```

### Key Components

**AuthRepository** - Stores credentials:
- Access + refresh tokens (JWT) in Keychain (secure)
- Server URL and user info in UserDefaults — this is BY DESIGN, so login
  state survives Keychain corruption; do not "fix" it by moving to Keychain

**SapphoAPI** - URLSession-based API client:
- All endpoints match the Android app's SapphoApi.kt
- Uses async/await
- Token automatically injected via Authorization header
- Snake_case JSON fields mapped via CodingKeys

**AudioPlayerService** - AVFoundation audio player:
- Background audio via AVAudioSession
- Lock screen controls via MPRemoteCommandCenter
- Progress syncs every 20 seconds (matching Android)
- Failed syncs queue in `ProgressStore`, scoped to the account (server + user id),
  and replay with `isReplay: true` so the server only lets them move forward.
  Logout (`prepareForLogout()`) sends the final position, then clears the queue.
- Start position = newer of server `progress.updated_at` and the locally saved
  position (`ProgressReconciler`). Play on the already-loaded book resumes it.
- End of audio marks the book finished only within 60 s of the known duration
  (`PlaybackCompletionPolicy`); an early end keeps the position and shows an error.
- Never auto-resumes on route changes; interruption end resumes only if
  `.shouldResume` AND it was playing.
- Sleep timer support
- Stream choice (`Domain/StreamingPolicy.swift`, unit tested): downloaded → local
  file; cellular / expensive / Low Data Mode → HLS `hls/master.m3u8`; "Data
  saver" setting (`dataSaver`, default off) → HLS `?prefer=low` on any network;
  otherwise progressive `/stream`. MP3 (`file_path` extension, or a 415 seen
  this session) → `/stream`. Decided per player item, so CarPlay uses it too.
- HLS failure: AVPlayer hides the server's status, so the app GETs the master
  itself (`probeHLSMaster`): 404 under a loaded playlist / new `X-File-Version`
  or 401 → reload the master (max 2); 415 or anything else → `/stream` at the
  same position for the rest of that play. Seeks use zero tolerance
  (`SeekPolicy`) so positions match across modes (HLS shares the timeline).

The pure rules live in `Domain/PlaybackPolicy.swift` and `Domain/StreamingPolicy.swift` and are unit tested.

**DownloadManager** - Offline downloads:
- Background URLSession, recreated at launch (and from
  `handleEventsForBackgroundURLSession`); in-flight metadata persisted to `pending.json`
- Rejects non-200/206 responses, error bodies, truncated and too-short files
  (`DownloadValidator`); audits existing files on launch
- Re-downloads when the server's `file_size` changes (replaced or merged file)
- Stores files in Application Support
- Player checks for local files first

**HomeFeedStore** (`Domain/HomeFeed.swift`) - Home feed shared by the phone and CarPlay:
- Four sections load in parallel, each with its own 12 s deadline, and publish as
  each answers; a failed section keeps its last books and is marked failed
- Last good feed saved per account (Application Support/HomeFeed), so both
  screens open with it; cleared on logout
- CarPlay Home is built from it + downloads + current book with no network wait
  (`CarPlayHomeLayout`, unit tested); covers are `?width=120` thumbnails via
  `CoverThumbnailLoader` (3 at a time, shared `ImageCache`)
- CarPlay taps start playback immediately (`CarPlayPlaybackStarter`); the
  server copy of the book is fetched afterwards (`refreshAfterImmediateStart`)

**Auth semantics:** 401 clears the session (unless it came back on a just-refreshed
token); 403 never does. A 403 with `must_change_password` (or the login response
flag) shows `ChangePasswordRequiredView`. Every request carries `X-Device-Name`
(percent-encoded) and `X-App-Version`.

**Versioning / CI:** see `docs/CI.md`. Versions live in `project.yml` only.

### State Management

Uses Swift's `@Observable` macro (iOS 17+):

```swift
@Observable
class AuthRepository {
    var serverURL: URL?
    var token: String?
    var isAuthenticated: Bool { token != nil }
}

// In views
@Environment(AuthRepository.self) private var authRepository
```

### API Endpoints

All endpoints from the Sappho server, matching Android implementation:

**Auth:** login, register
**Library:** audiobooks, recent, in-progress, finished, up-next
**Progress:** GET/POST/DELETE progress, chapters
**Collections:** CRUD, add/remove items
**Favorites:** toggle, list
**Ratings:** get/set/delete
**Profile:** get/update, avatar, stats
**Admin:** users, settings, library scan, backups

### Theme

Dark theme matching Android/web:

```swift
Color.sapphoBackground  // #0A0E1A
Color.sapphoSurface     // #1a1a1a
Color.sapphoPrimary     // #3B82F6
Color.sapphoTextHigh    // #E0E7F1
Color.sapphoTextMuted   // #9ca3af
```

## Development Notes

### JSON Snake Case

Server returns snake_case, models use camelCase with CodingKeys:

```swift
struct Audiobook: Codable {
    let coverImage: String?

    enum CodingKeys: String, CodingKey {
        case coverImage = "cover_image"
    }
}
```

### Media URL Authentication

Cover images and streams authenticate via the `Authorization` header (never a
query-string token). AVPlayer sends `AVURLAssetHTTPHeaderFieldsKey` headers on
every HLS request (master, media playlist, init, segments) — verified on iOS 26.
`SapphoAPI` exposes plain URLs plus headers to attach:

```swift
func coverURL(for audiobookId: Int) -> URL? {
    guard let baseURL = authRepository.serverURL else { return nil }
    return baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)/cover")
}

var authHeaders: [String: String] {
    guard let token = authRepository.token else { return [:] }
    return ["Authorization": "Bearer \(token)"]
}
```

### Background Audio

Configured in AppDelegate and Info.plist:
- `AVAudioSession.Category.playback`
- `UIBackgroundModes: audio`

### Regenerating Project

If you modify project.yml:

```bash
xcodegen generate
```

This regenerates the .xcodeproj from the project.yml spec.

## Common Tasks

### Adding a New Screen

1. Create view in appropriate Presentation/ folder
2. Add navigation link or sheet presentation
3. Wire up API calls and state

### Adding a New API Endpoint

1. Add method to SapphoAPI.swift
2. Add any needed request/response types
3. Use async/await pattern matching existing methods

### Modifying the Theme

Edit `Presentation/Components/Theme.swift` - colors, fonts, and common styles.

## Environment Variables

No build-time env vars required. Server URL is configured at runtime via login screen.

## Dependencies

None. The app has no Swift Package Manager (or other third-party) dependencies —
everything uses native iOS frameworks (SwiftUI, AVFoundation, CarPlay, MediaPlayer,
Network, Security).
