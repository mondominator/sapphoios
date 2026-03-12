# Sappho iOS

Native iOS client for the [Sappho](https://github.com/mondominator/sappho) self-hosted audiobook server.

![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![iOS](https://img.shields.io/badge/iOS-17.0+-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Stream or download audiobooks from your Sappho server
- Background audio playback with lock screen controls
- Chapter navigation and bookmarking
- Adjustable playback speed (0.25x - 3x) with fine-tune controls
- Sleep timer
- Progress sync across devices
- Offline downloads
- Library browsing by author, series, genre, and collections
- AirPlay support
- Dark theme matching the Sappho web app

## Screenshots

*Coming soon*

## Requirements

- iOS 17.0+
- Xcode 15.0+
- A running [Sappho server](https://github.com/mondominator/sappho)

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/mondominator/sapphoios.git
cd sapphoios
```

### 2. Generate the Xcode project

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`:

```bash
brew install xcodegen
xcodegen generate
```

### 3. Open in Xcode

```bash
open Sappho.xcodeproj
```

### 4. Build and run

Select your target device or simulator and press **Cmd+R**.

On first launch, enter your Sappho server URL and credentials to connect.

## Architecture

The app follows a clean architecture pattern with SwiftUI:

```
Sappho/
├── App/                    # Entry point
├── Data/
│   ├── Remote/            # API client (URLSession + async/await)
│   └── Repository/        # Auth storage (Keychain)
├── Domain/Model/          # Data models
├── Presentation/          # SwiftUI views
│   ├── Home/              # Main feed
│   ├── Library/           # Browse by author/series/genre
│   ├── Detail/            # Audiobook detail
│   ├── Player/            # Full & mini player
│   ├── Search/            # Search
│   ├── Profile/           # User settings & admin
│   └── Components/        # Shared UI & theme
├── Service/
│   ├── AudioPlayerService # AVFoundation playback
│   └── DownloadManager    # Offline downloads
└── Cast/                  # Chromecast (Google Cast SDK)
```

**State management** uses Swift's `@Observable` macro with `@Environment` injection.

## Related Projects

- [Sappho Server](https://github.com/mondominator/sappho) - The audiobook server (Node.js)
- [Sappho Android](https://github.com/mondominator/sapphoapp) - Android client (Kotlin/Jetpack Compose)

## Contributing

Contributions are welcome! Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
