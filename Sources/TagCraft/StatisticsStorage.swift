import Foundation

struct StatisticsStorage {
    static func open(directory: URL) throws -> (store: LibraryStore, migrated: Bool) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("library-statistics.sqlite")
        var migrated = false
        // Temporary hook: remove this block and LegacyStatisticsMigration.swift after migration.
        if !FileManager.default.fileExists(atPath: destination.path),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("library-statistics.json").path) {
            migrated = try LegacyStatisticsMigration.migrate(directory: directory)
        }
        return (try LibraryStore(url: destination), migrated)
    }
}
