import Foundation

// The Home feed (Continue Listening, Up Next, Recently Added, Listen Again),
// shared by the phone's Home tab and CarPlay's Home.
//
// Why this exists: CarPlay used to fetch the four lists one after another,
// each on URLSession's default 60 s timeout, and only filled its Home once all
// four had answered. On a slow cellular link that left CarPlay's Home empty
// for minutes, while the phone (four requests in parallel, 10 s cap) showed
// something. Neither screen remembered the last feed, so every cold start
// began from nothing.
//
// Now each section loads on its own, with its own short deadline, and is
// published as soon as it answers. A slow or failing section keeps the books
// it last had and is marked as not refreshed; it never holds up the others.
// The last good feed is saved per account, so both screens open with it.

// MARK: - Sections

enum HomeSectionKind: String, CaseIterable, Codable, Sendable {
    case continueListening
    case upNext
    case recentlyAdded
    case listenAgain

    var title: String {
        switch self {
        case .continueListening: return "Continue Listening"
        case .upNext: return "Up Next"
        case .recentlyAdded: return "Recently Added"
        case .listenAgain: return "Listen Again"
        }
    }
}

enum HomeSectionFailure: Equatable, Sendable {
    /// No answer before the section's deadline.
    case timedOut
    /// The server could not be reached at all.
    case unreachable
    /// The server answered with an error (HTTP failure, bad body, auth).
    case server(String)

    /// Timeouts and unreachable servers mean "offline", not "broken".
    var isConnectivity: Bool {
        switch self {
        case .timedOut, .unreachable: return true
        case .server: return false
        }
    }

    static func classify(_ error: Error) -> HomeSectionFailure {
        if error is DeadlineExceeded { return .timedOut }
        if error is CancellationError { return .timedOut }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut ? .timedOut : .unreachable
        }
        if case APIError.networkError(let inner) = error {
            if let urlError = inner as? URLError, urlError.code == .timedOut { return .timedOut }
            return .unreachable
        }
        return .server(error.localizedDescription)
    }
}

enum HomeSectionStatus: Equatable, Sendable {
    /// Nothing fetched this session (books, if any, came from the saved feed).
    case notLoaded
    case loading
    case loaded
    case failed(HomeSectionFailure)
}

struct HomeSectionState: Equatable {
    /// What to show: the last good answer, kept through later failures.
    var books: [Audiobook] = []
    var status: HomeSectionStatus = .notLoaded
    /// When `books` was last fetched from the server (nil = never).
    var updatedAt: Date?

    static func == (lhs: HomeSectionState, rhs: HomeSectionState) -> Bool {
        lhs.books.map(\.id) == rhs.books.map(\.id)
            && lhs.status == rhs.status
            && lhs.updatedAt == rhs.updatedAt
    }
}

// MARK: - Deadline

struct DeadlineExceeded: Error, Equatable {}

enum Deadline {
    /// Run `operation`, giving up after `seconds`. The caller gets
    /// `DeadlineExceeded` the moment the deadline passes, without waiting for
    /// the operation to wind down (a task group would wait for it); the
    /// operation is cancelled, which URLSession requests honour.
    static func run<T>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeOnce<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.attach(continuation)
                let work = Task {
                    do { gate.resume(.success(try await operation())) } catch { gate.resume(.failure(error)) }
                }
                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    gate.resume(.failure(DeadlineExceeded()))
                }
                gate.onFinish {
                    work.cancel()
                    timer.cancel()
                }
            }
        } onCancel: {
            gate.resume(.failure(CancellationError()))
        }
    }
}

/// Resumes a continuation exactly once, whichever side gets there first.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var finished = false
    private var cleanup: (() -> Void)?

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func onFinish(_ cleanup: @escaping () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            cleanup()
            return
        }
        self.cleanup = cleanup
        lock.unlock()
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { pending = result }
        let cleanup = self.cleanup
        self.cleanup = nil
        lock.unlock()
        continuation?.resume(with: result)
        cleanup?()
    }
}

// MARK: - Saved feed

/// The last good feed, saved to disk per account.
struct HomeFeedSnapshot: Codable {
    var sections: [String: [Audiobook]]
    var updatedAt: [String: Date]
}

// MARK: - Store

/// Holds the Home feed for the phone and CarPlay alike.
@MainActor
@Observable
final class HomeFeedStore {
    typealias Fetcher = @Sendable (HomeSectionKind) async throws -> [Audiobook]

    static let shared = HomeFeedStore()

    /// Short on purpose: these are lists for a screen someone is looking at.
    /// Better to show the saved feed with "couldn't refresh" than a spinner.
    static let defaultSectionTimeout: TimeInterval = 12

    private(set) var sections: [HomeSectionKind: HomeSectionState]

    @ObservationIgnored private var account: String?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var listeners: [UUID: (HomeSectionKind?) -> Void] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeFeed", isDirectory: true)
        self.sections = Dictionary(uniqueKeysWithValues: HomeSectionKind.allCases.map { ($0, HomeSectionState()) })
    }

    func books(_ kind: HomeSectionKind) -> [Audiobook] {
        sections[kind]?.books ?? []
    }

    func state(_ kind: HomeSectionKind) -> HomeSectionState {
        sections[kind] ?? HomeSectionState()
    }

    var hasAnyBooks: Bool {
        sections.values.contains { !$0.books.isEmpty }
    }

    /// Every section that was asked for this session failed for lack of a
    /// connection (and none succeeded).
    var allFailedForConnectivity: Bool {
        let states = Array(sections.values)
        return !states.isEmpty && states.allSatisfy {
            if case .failed(let failure) = $0.status { return failure.isConnectivity }
            return false
        }
    }

    /// The server's error, when every section failed with one.
    var serverErrorMessage: String? {
        var message: String?
        for state in sections.values {
            guard case .failed(.server(let text)) = state.status else { return nil }
            message = text
        }
        return message
    }

    /// Sections whose last refresh failed.
    var failedSections: [HomeSectionKind] {
        HomeSectionKind.allCases.filter {
            if case .failed = state($0).status { return true }
            return false
        }
    }

    // MARK: Listeners (CarPlay)

    /// Called after each section changes (nil = everything changed, e.g. an
    /// account switch). Returns a token for `removeListener`.
    @discardableResult
    func addListener(_ listener: @escaping (HomeSectionKind?) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func notify(_ kind: HomeSectionKind?) {
        for listener in listeners.values { listener(kind) }
    }

    // MARK: Account

    /// Switch to `account`'s saved feed. No-op if it's already active.
    func activate(account: String?) {
        guard account != self.account else { return }
        inFlight?.cancel()
        inFlight = nil
        self.account = account
        var fresh = Dictionary(uniqueKeysWithValues: HomeSectionKind.allCases.map { ($0, HomeSectionState()) })
        if let account, let snapshot = loadSnapshot(account: account) {
            for kind in HomeSectionKind.allCases {
                fresh[kind]?.books = snapshot.sections[kind.rawValue] ?? []
                fresh[kind]?.updatedAt = snapshot.updatedAt[kind.rawValue]
            }
        }
        sections = fresh
        notify(nil)
    }

    // MARK: Refresh

    /// Refresh every section in parallel. Each section is published the moment
    /// it answers (or misses its own deadline); a failed section keeps its
    /// previous books. A call while a refresh is running joins that refresh.
    func refresh(timeout: TimeInterval = HomeFeedStore.defaultSectionTimeout, fetch: @escaping Fetcher) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(timeout: timeout, fetch: fetch)
        }
        inFlight = task
        await task.value
        if inFlight == task { inFlight = nil }
    }

    private func performRefresh(timeout: TimeInterval, fetch: @escaping Fetcher) async {
        let account = self.account
        for kind in HomeSectionKind.allCases {
            sections[kind]?.status = .loading
        }
        notify(nil)

        await withTaskGroup(of: (HomeSectionKind, Result<[Audiobook], Error>).self) { group in
            for kind in HomeSectionKind.allCases {
                group.addTask {
                    do {
                        let books = try await Deadline.run(seconds: timeout) { try await fetch(kind) }
                        return (kind, .success(books))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }
            // Publish each section as it lands, not when the slowest one does.
            for await (kind, result) in group {
                // Account switched mid-refresh: these answers belong to someone else.
                guard self.account == account, !Task.isCancelled else { continue }
                switch result {
                case .success(let books):
                    sections[kind] = HomeSectionState(books: books, status: .loaded, updatedAt: Date())
                    saveSnapshot()
                case .failure(let error):
                    sections[kind]?.status = .failed(HomeSectionFailure.classify(error))
                }
                notify(kind)
            }
        }
    }

    // MARK: Persistence

    private static let writeQueue = DispatchQueue(label: "com.sappho.homefeed.write", qos: .utility)

    /// Blocks until every queued snapshot write has reached disk (tests).
    static func waitForPendingWrites() {
        writeQueue.sync {}
    }

    private func fileURL(account: String) -> URL {
        // Account keys contain the server URL; hash for a safe file name.
        let hash = account.utf8.reduce(into: UInt64(5381)) { $0 = $0 &* 33 &+ UInt64($1) }
        return directory.appendingPathComponent("feed-\(String(hash, radix: 16)).json")
    }

    private func loadSnapshot(account: String) -> HomeFeedSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(account: account)) else { return nil }
        return try? JSONDecoder().decode(HomeFeedSnapshot.self, from: data)
    }

    private func saveSnapshot() {
        guard let account else { return }
        var snapshot = HomeFeedSnapshot(sections: [:], updatedAt: [:])
        for kind in HomeSectionKind.allCases {
            let state = state(kind)
            guard let updatedAt = state.updatedAt else { continue }
            snapshot.sections[kind.rawValue] = state.books
            snapshot.updatedAt[kind.rawValue] = updatedAt
        }
        let url = fileURL(account: account)
        let directory = self.directory
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Serial: snapshots must land in the order they were taken.
        Self.writeQueue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Forget the saved feed for `account` (logout).
    func clear(account: String) {
        try? FileManager.default.removeItem(at: fileURL(account: account))
        if self.account == account {
            activate(account: nil)
        }
    }
}

extension HomeFeedStore {
    /// The fetcher backed by the real API. Limits match what each screen shows.
    static func apiFetcher(_ api: SapphoAPI) -> Fetcher {
        { kind in
            switch kind {
            case .continueListening: return try await api.getInProgress(limit: 25)
            case .upNext: return try await api.getUpNext()
            case .recentlyAdded: return try await api.getRecentlyAdded(limit: 10)
            case .listenAgain: return try await api.getFinished(limit: 10)
            }
        }
    }
}
