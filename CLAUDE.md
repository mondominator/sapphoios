# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Sappho iOS is a native Swift/SwiftUI iOS app for the Sappho audiobook server. It provides feature parity with the Android app (sapphoapp), including:

- Authentication with dynamic server URL
- Library browsing (all, series, authors, genres, collections)
- Audio playback with background audio support
- Progress sync with server
- Offline downloads
- Chromecast and AirPlay support
- Sleep timer, playback speed control
- Lock screen / Now Playing controls

**Tech Stack:**
- Swift 5.9+ / SwiftUI
- iOS 17.0+ minimum
- AVFoundation for audio playback
- Google Cast SDK for Chromecast
- URLSession for networking
- Keychain for secure storage

## Build Commands

### Generate Xcode Project

```bash
# Generate/regenerate the Xcode project
xcodegen generate
```

### Building

```bash
# Build for simulator
xcodebuild -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 15' build

# Build for device (requires signing)
xcodebuild -scheme Sappho -destination 'generic/platform=iOS' build
```

### Running on Device/Simulator

Open `Sappho.xcodeproj` in Xcode and press Run, or:

```bash
# Run on simulator
xcodebuild -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 15' build
xcrun simctl boot "iPhone 15"
xcrun simctl install booted build/Debug-iphonesimulator/Sappho.app
xcrun simctl launch booted com.sappho.audiobooks
```

### Testing

```bash
# Run unit tests
xcodebuild test -scheme Sappho -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Architecture Overview

### Project Structure

```
Sappho/
├── App/                    # App entry point, AppDelegate
├── Data/
│   ├── Remote/            # SapphoAPI (URLSession)
│   └── Repository/        # AuthRepository (Keychain)
├── Domain/Model/          # Data models (Audiobook, User, etc.)
├── Presentation/
│   ├── Login/
│   ├── Home/
│   ├── Library/
│   ├── Detail/
│   ├── Player/
│   ├── Search/
│   ├── Profile/
│   └── Components/        # Shared UI, Theme
├── Service/
│   ├── AudioPlayerService.swift
│   └── DownloadManager.swift
└── Cast/                  # Chromecast integration
```

### Key Components

**AuthRepository** - Stores credentials in Keychain:
- Server URL (dynamically configured at login)
- Auth token (JWT)
- Current user info

**SapphoAPI** - URLSession-based API client:
- All endpoints match the Android app's SapphoApi.kt
- Uses async/await
- Token automatically injected via Authorization header
- Snake_case JSON fields mapped via CodingKeys

**AudioPlayerService** - AVFoundation audio player:
- Background audio via AVAudioSession
- Lock screen controls via MPRemoteCommandCenter
- Progress syncs every 20 seconds (matching Android)
- Sleep timer support

**DownloadManager** - Offline downloads:
- Background URLSession for downloads
- Stores files in Application Support
- Player checks for local files first

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

Cover images and streams require token via query string:

```swift
func coverURL(for audiobookId: Int) -> URL? {
    var components = URLComponents(...)
    components.queryItems = [URLQueryItem(name: "token", value: token)]
    return components.url
}
```

### Background Audio

Configured in AppDelegate and Info.plist:
- `AVAudioSession.Category.playback`
- `UIBackgroundModes: audio, fetch`

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

**Swift Package Manager:**
- google-cast-sdk (Chromecast)

Everything else uses native iOS frameworks.
