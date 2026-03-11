import SwiftUI

// MARK: - Image Cache

/// In-memory image cache backed by NSCache for automatic eviction under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        let cost = image.jpegData(compressionQuality: 1)?.count ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

// MARK: - Image Loader

@MainActor
@Observable
final class ImageLoader {
    var image: UIImage?
    var isLoading = false
    var failed = false

    private var currentURL: URL?
    private var task: Task<Void, Never>?

    func load(url: URL?) {
        guard let url else {
            failed = true
            return
        }

        // Same URL already loaded or loading
        if url == currentURL && (image != nil || isLoading) { return }

        cancel()
        currentURL = url

        let key = url.absoluteString

        // Check cache first
        if let cached = ImageCache.shared.image(for: key) {
            self.image = cached
            return
        }

        isLoading = true
        failed = false

        task = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }

                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode,
                      let uiImage = UIImage(data: data) else {
                    self.failed = true
                    self.isLoading = false
                    return
                }

                ImageCache.shared.setImage(uiImage, for: key)
                self.image = uiImage
                self.isLoading = false
            } catch {
                if !Task.isCancelled {
                    self.failed = true
                    self.isLoading = false
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - CoverImage View

/// Reusable cover image view with in-memory caching, loading state, and error fallback.
struct CoverImage: View {
    @Environment(\.sapphoAPI) private var api
    let audiobookId: Int
    var cornerRadius: CGFloat = 8

    @State private var loader = ImageLoader()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if loader.failed {
                    placeholder(size: min(geo.size.width, geo.size.height))
                } else {
                    placeholder(size: min(geo.size.width, geo.size.height))
                        .overlay(
                            ProgressView()
                                .tint(.sapphoTextMuted)
                                .scaleEffect(0.8)
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onAppear {
            loader.load(url: api?.coverURL(for: audiobookId))
        }
        .onChange(of: audiobookId) { _, newId in
            loader.load(url: api?.coverURL(for: newId))
        }
    }

    private func placeholder(size: CGFloat) -> some View {
        Rectangle()
            .fill(Color.sapphoSurface)
            .overlay(
                Image(systemName: "book.closed.fill")
                    .font(.system(size: max(size * 0.25, 14)))
                    .foregroundColor(.sapphoTextMuted)
            )
    }
}
