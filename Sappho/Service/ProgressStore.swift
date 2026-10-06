import Foundation

/// Positions saved on this device, and progress updates waiting to be sent,
/// both scoped to one account (server + user).
///
/// Scoping matters: the offline queue used to be one global dictionary keyed
/// by book id, so a sync that failed during logout was replayed into whichever
/// account logged in next -- user A's position posted into user B's library,
/// or into a different server where that id is another book entirely.
final class ProgressStore {
    private let defaults: UserDefaults

    private static let localKey = "localProgressByAccount"
    private static let pendingKey = "pendingProgressByAccount"
    /// The old, unscoped queue: `[bookId: position]`.
    static let legacyPendingKey = "pendingProgressSync"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Local positions

    func localProgress(account: String, audiobookId: Int) -> LocalProgress? {
        guard let entry = localTable[account]?[String(audiobookId)] else { return nil }
        return LocalProgress(position: entry.position, updatedAt: Date(timeIntervalSince1970: entry.updatedAt))
    }

    func saveLocal(account: String, audiobookId: Int, position: Int, at date: Date = Date()) {
        var table = localTable
        table[account, default: [:]][String(audiobookId)] = Entry(position: position, updatedAt: date.timeIntervalSince1970)
        localTable = table
    }

    // MARK: Pending (offline) queue

    func pending(account: String) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (id, entry) in pendingTable[account] ?? [:] {
            if let bookId = Int(id) { result[bookId] = entry.position }
        }
        return result
    }

    func savePending(account: String, audiobookId: Int, position: Int, at date: Date = Date()) {
        var table = pendingTable
        table[account, default: [:]][String(audiobookId)] = Entry(position: position, updatedAt: date.timeIntervalSince1970)
        pendingTable = table
    }

    func removePending(account: String, audiobookId: Int) {
        var table = pendingTable
        table[account]?.removeValue(forKey: String(audiobookId))
        if table[account]?.isEmpty == true { table.removeValue(forKey: account) }
        pendingTable = table
    }

    /// Forget everything queued and saved for an account (logout).
    func clear(account: String) {
        var pending = pendingTable
        pending.removeValue(forKey: account)
        pendingTable = pending
        var local = localTable
        local.removeValue(forKey: account)
        localTable = local
    }

    /// The pre-scoping queue has no owner recorded. Attribute it to the account
    /// that is signed in now (the only plausible owner, since it was written by
    /// this install), or drop it when nobody is. The server's forward-only
    /// replay guard bounds the damage either way.
    func migrateLegacyPending(to account: String?) {
        guard let legacy = defaults.dictionary(forKey: Self.legacyPendingKey) as? [String: Int] else { return }
        defaults.removeObject(forKey: Self.legacyPendingKey)
        guard let account else { return }
        for (id, position) in legacy {
            if let bookId = Int(id) { savePending(account: account, audiobookId: bookId, position: position) }
        }
    }

    // MARK: Storage

    private struct Entry: Codable {
        let position: Int
        let updatedAt: TimeInterval
    }

    private typealias Table = [String: [String: Entry]]

    private var localTable: Table {
        get { read(Self.localKey) }
        set { write(newValue, Self.localKey) }
    }

    private var pendingTable: Table {
        get { read(Self.pendingKey) }
        set { write(newValue, Self.pendingKey) }
    }

    private func read(_ key: String) -> Table {
        guard let data = defaults.data(forKey: key),
              let table = try? JSONDecoder().decode(Table.self, from: data) else { return [:] }
        return table
    }

    private func write(_ table: Table, _ key: String) {
        if let data = try? JSONEncoder().encode(table) {
            defaults.set(data, forKey: key)
        }
    }
}
