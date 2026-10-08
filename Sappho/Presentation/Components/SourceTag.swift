import SwiftUI

/// A small capsule naming the linked server a book comes from ("Robert").
/// Shown only for remote books; this server's own books show nothing.
/// When the book can't be played right now it reads "Robert · Offline".
struct SourceTag: View {
    enum Style {
        /// On a cover: dark translucent backing so it reads over any art.
        case overlay
        /// In a text row.
        case inline
        /// Book details: "From Robert's library".
        case detail
    }

    let source: BookSource
    var isOffline: Bool = false
    var style: Style = .overlay

    private var text: String {
        let name = style == .detail ? "From \(source.name)'s library" : source.name
        return isOffline ? "\(name) · Offline" : name
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isOffline ? "icloud.slash" : "link")
                .font(style == .detail ? .sapphoTiny : .sapphoMicro)
            Text(text)
                .font(style == .detail ? .sapphoSmallMedium : .sapphoTinySemibold)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundColor(style == .overlay ? .white.opacity(0.9) : .sapphoTextMedium)
        .padding(.horizontal, style == .detail ? 10 : 6)
        .padding(.vertical, style == .detail ? 4 : 2)
        .background(
            Capsule().fill(style == .overlay ? Color.black.opacity(0.6) : Color.sapphoSurfaceElevated)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOffline ? "From \(source.name)'s library, offline" : "From \(source.name)'s library")
    }
}

extension Audiobook {
    /// The source tag for a remote book, nil for a local one.
    @ViewBuilder
    func sourceTag(style: SourceTag.Style = .overlay) -> some View {
        if let source {
            SourceTag(source: source, isOffline: !isAvailable, style: style)
        }
    }

    /// Appended to a card's combined accessibility label.
    var sourceAccessibilitySuffix: String {
        guard let source else { return "" }
        return isAvailable ? ", from \(source.name)'s library" : ", from \(source.name)'s library, offline"
    }
}

extension View {
    /// Dims a book that can't be played right now (see
    /// `LinkedServerPolicy.isPlayable`).
    func dimmedWhenUnavailable(_ book: Audiobook) -> some View {
        let playable = LinkedServerPolicy.isPlayable(book, isDownloaded: DownloadManager.shared.isDownloaded(book.id))
        return self
            .opacity(playable ? 1 : 0.5)
            .saturation(playable ? 1 : 0)
    }
}
