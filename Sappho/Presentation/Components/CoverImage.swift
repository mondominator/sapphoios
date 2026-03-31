import SwiftUI

// MARK: - Image Cache

/// Two-tier image cache: in-memory (NSCache) + on-disk (Caches directory).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let diskURL: URL

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskURL = caches.appendingPathComponent("CoverImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskURL, withIntermediateDirectories: true)
    }

    func image(for key: String) -> UIImage? {
        // Check memory first
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        // Check disk
        let file = diskURL.appendingPathComponent(diskKey(for: key))
        guard let data = try? Data(contentsOf: file),
              let image = UIImage(data: data) else { return nil }
        // Promote to memory cache
        let cost = data.count
        memory.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }

    func setImage(_ image: UIImage, for key: String) {
        let cost = image.jpegData(compressionQuality: 1)?.count ?? 0
        memory.setObject(image, forKey: key as NSString, cost: cost)
        // Write to disk in background
        let file = diskURL.appendingPathComponent(diskKey(for: key))
        DispatchQueue.global(qos: .utility).async {
            if let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    func removeImage(for key: String) {
        memory.removeObject(forKey: key as NSString)
        let file = diskURL.appendingPathComponent(diskKey(for: key))
        try? FileManager.default.removeItem(at: file)
    }

    private func diskKey(for key: String) -> String {
        // SHA256-like hash using built-in — use simple hash for filename safety
        let hash = key.utf8.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
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

    func load(url: URL?, headers: [String: String] = [:]) {
        guard let url else {
            failed = true
            return
        }

        // Same URL already loaded or loading
        if url == currentURL && (image != nil || isLoading) { return }

        cancel()
        currentURL = url

        let key = url.absoluteString

        // Check cache first (memory + disk)
        if let cached = ImageCache.shared.image(for: key) {
            self.image = cached
            return
        }

        isLoading = true
        failed = false

        task = Task {
            do {
                var request = URLRequest(url: url)
                for (field, value) in headers {
                    request.setValue(value, forHTTPHeaderField: field)
                }
                let (data, response) = try await URLSession.shared.data(for: request)
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
        isLoading = false
    }
}

// MARK: - CoverImage View

/// Reusable cover image view with two-tier caching, loading state, and error fallback.
struct CoverImage: View {
    @Environment(\.sapphoAPI) private var api
    let audiobookId: Int
    var cornerRadius: CGFloat = 8
    var contentMode: ContentMode = .fit
    var refreshTrigger: Int = 0

    @State private var loader = ImageLoader()

    /// Check cache synchronously so the first render already has the image
    /// (avoids placeholder flash in lazy containers).
    private var cachedImage: UIImage? {
        guard let url = api?.coverURL(for: audiobookId) else { return nil }
        return ImageCache.shared.image(for: url.absoluteString)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = loader.image ?? cachedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
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
            loader.load(url: api?.coverURL(for: audiobookId), headers: api?.authHeaders ?? [:])
        }
        .onChange(of: audiobookId) { _, newId in
            loader.load(url: api?.coverURL(for: newId), headers: api?.authHeaders ?? [:])
        }
        .onChange(of: refreshTrigger) { _, _ in
            // Invalidate cache and reload
            if let url = api?.coverURL(for: audiobookId) {
                ImageCache.shared.removeImage(for: url.absoluteString)
            }
            loader = ImageLoader()
            loader.load(url: api?.coverURL(for: audiobookId), headers: api?.authHeaders ?? [:])
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
