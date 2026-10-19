import Foundation

/// Temporary one-time bridge. Remove after the existing user's JSON has been migrated.
/// The source JSON is never edited, renamed or deleted.
struct LegacyStatisticsMigration {
    static func migrate(directory: URL) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("library-statistics.sqlite")
        if fm.fileExists(atPath: destination.path) { return false }
        let source = directory.appendingPathComponent("library-statistics.json")
        guard fm.fileExists(atPath: source.path) else { return false }
        let original = try Data(contentsOf: source)
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: original)
        let temporary = directory.appendingPathComponent(".statistics-import-" + UUID().uuidString + ".sqlite")
        defer {
            for suffix in ["", "-wal", "-shm", "-journal"] { try? fm.removeItem(atPath: temporary.path + suffix) }
        }
        let staging = try LibraryStore(url: temporary)
        try staging.importLegacy(snapshot)
        guard try staging.integrityCheck() else { throw TagError(message: "SQLite verification failed. Original JSON is unchanged.") }
        try staging.closeForPublication()
        // If the old app is still completing a scan, don't publish an obsolete import.
        guard try Data(contentsOf: source) == original else { throw TagError(message: "The JSON cache changed during migration. Let the old scan finish, then restart to retry.") }
        do { try fm.moveItem(at: temporary, to: destination) }
        catch {
            if fm.fileExists(atPath: destination.path) { return false }
            throw error
        }
        return true
    }
}
