import Foundation

struct SQLiteChecks {
    static func run() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("TagCraft-SQLite-" + UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let migratedDir = base.appendingPathComponent("Migration")
        try fm.createDirectory(at: migratedDir, withIntermediateDirectories: true)
        let migrationCount = ProcessInfo.processInfo.environment["TAGCRAFT_LARGE_SQL_CHECK"] == "1" ? 32_546 : 1_000
        var records: [LibraryRecord] = []
        for i in 0..<migrationCount {
            let tags = Tags(extra: ["TPOS": "2/2", "TCOM": "Composer \(i)"], title: "Song \(i)\n\"quoted\"", artist: i == 0 ? "Guest\0Other" : "Artist \(i % 20)", album: "Album \(i / 10)", albumArtist: "Artist \(i % 20)", year: "2020", genre: i == 0 ? " \nRock\t" : "Genre \(i % 4)", track: "\(i % 10 + 1)/10")
            records.append(.init(path: "/Test Library/é/曲/\(i) 'quoted'.mp3", bytes: Int64(10_000+i), modified: Date(timeIntervalSinceReferenceDate: 800_000_000.123456), tags: tags, hasArtwork: i % 2 == 0, duration: Double(i + 60), bitrate: 128, sampleRate: 44_100, audioRead: true))
        }
        let legacy = LibraryScanner.summarize(URL(fileURLWithPath: "/Test Library"), records: records, includeAudio: true)
        let json = try JSONEncoder().encode(legacy)
        let jsonURL = migratedDir.appendingPathComponent("library-statistics.json")
        try json.write(to: jsonURL)
        let migrated = try StatisticsStorage.open(directory: migratedDir)
        check(migrated.migrated)
        let imported = try migrated.store.snapshot(root: legacy.root)!
        check(imported.tracks == legacy.tracks && imported.bytes == legacy.bytes && imported.artists == legacy.artists)
        check(imported.records == nil && imported.findings == nil && imported.databaseBacked == true)
        let importedRecords = try migrated.store.records(scanID: imported.databaseScanID!)
        check(Dictionary(uniqueKeysWithValues: importedRecords.map { ($0.path,$0) }) == Dictionary(uniqueKeysWithValues: records.map { ($0.path,$0) }))
        check(try migrated.store.findings(scanID: imported.databaseScanID!).count == legacy.findings?.count)
        check(try Data(contentsOf: jsonURL) == json)
        check(try migrated.store.integrityCheck())
        if let reason = legacy.findings?.first?.reason {
            let subset = try migrated.store.findings(scanID: imported.databaseScanID!, reason: reason)
            check(!subset.isEmpty && subset.allSatisfy { $0.reason == reason })
            check(Set(subset.map(\.id)) == Set(legacy.findings!.filter { $0.reason == reason }.map(\.id)))
        }
        check(try migrated.store.findings(scanID: imported.databaseScanID!, reason: "% _ ? 'not an issue'").isEmpty)
        let again = try StatisticsStorage.open(directory: migratedDir)
        check(try !again.migrated && (try again.store.snapshot(root: legacy.root))?.tracks == migrationCount)
        let csv = CSVReport.inventory(LibrarySnapshot(records: importedRecords, root: legacy.root, updated: imported.updated))
        check(csv.count == migrationCount + 1 && CSVReport.encode(csv).contains("quoted"))
        print("SQLite migration verified (\(migrationCount) records): all record fields, Unicode/NUL text, summaries, health counts, JSON unchanged and idempotent startup.")

        for malformed in [false,true] {
            let badDir = base.appendingPathComponent(malformed ? "Bad JSON" : "Mismatched Totals")
            try fm.createDirectory(at: badDir, withIntermediateDirectories: true)
            var bad = legacy; bad.tracks += 1
            let bytes = malformed ? Data("broken JSON".utf8) : try JSONEncoder().encode(bad)
            let source = badDir.appendingPathComponent("library-statistics.json")
            try bytes.write(to: source)
            check((try? StatisticsStorage.open(directory: badDir)) == nil)
            check(!fm.fileExists(atPath: badDir.appendingPathComponent("library-statistics.sqlite").path))
            check(try Data(contentsOf: source) == bytes)
        }
        let duplicateReportDir = base.appendingPathComponent("Duplicate Legacy Findings")
        try fm.createDirectory(at: duplicateReportDir, withIntermediateDirectories: true)
        var duplicateReport = legacy
        if let firstFinding = legacy.findings?.first { duplicateReport.findings = [firstFinding, firstFinding] }
        let duplicateJSON = try JSONEncoder().encode(duplicateReport)
        try duplicateJSON.write(to: duplicateReportDir.appendingPathComponent("library-statistics.json"))
        check((try? StatisticsStorage.open(directory: duplicateReportDir)) == nil)
        check(!fm.fileExists(atPath: duplicateReportDir.appendingPathComponent("library-statistics.sqlite").path))
        check(try Data(contentsOf: duplicateReportDir.appendingPathComponent("library-statistics.json")) == duplicateJSON)
        let futureURL = base.appendingPathComponent("future.sqlite")
        do { let connection = try SQLiteConnection(futureURL); try connection.execute("PRAGMA user_version=99"); try connection.closeForPublication() }
        let futureBytes = try Data(contentsOf: futureURL)
        check((try? LibraryStore(url: futureURL)) == nil)
        check(try Data(contentsOf: futureURL) == futureBytes)
        print("SQLite failed-import and newer-schema refusal checks passed; source JSON/database retained.")

        let root = base.appendingPathComponent("Music")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = Data([255,251,144,0,1,2,3])
        for i in 0..<100 {
            let tags = Tags(title: "Song \(i)", artist: i % 2 == 0 ? "Artist" : "artist", album: "Album", albumArtist: i % 3 == 0 ? "Artist" : "", year: "2020", genre: i == 0 ? " \nRock\t" : "Rock", track: "\(i+1)/100")
            try ID3(audio).writing(tags, original: audio).write(to: root.appendingPathComponent("\(i).mp3"))
        }
        let legacyFiles = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, cancellation: JobCancellation()) { _ in }
        let fileImportDir = base.appendingPathComponent("Real File Import")
        try fm.createDirectory(at: fileImportDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacyFiles).write(to: fileImportDir.appendingPathComponent("library-statistics.json"))
        let fileImport = try StatisticsStorage.open(directory: fileImportDir)
        check(fileImport.migrated)
        let reusedImport = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: fileImport.store, cancellation: JobCancellation()) { _ in }
        check(reusedImport.reusedRecords == 100)
        print("First SQLite rescan reused all 100 real-file records imported from JSON.")
        let scanDir = base.appendingPathComponent("Scans")
        var store = try StatisticsStorage.open(directory: scanDir).store
        let cancel = JobCancellation()
        let first = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(first.tracks == 100 && first.reusedRecords == 0)
        check(first.records == nil && first.databaseScanID != nil)
        let actualRecords = try store.records(scanID: first.databaseScanID!)
        let expected = LibraryScanner.summarize(root, records: actualRecords, includeAudio: false)
        check(first.artists == expected.artists && first.genres == expected.genres && first.years == expected.years && first.bytes == expected.bytes && first.albumCount == expected.albumCount)
        let actualFindings = try store.findings(scanID: first.databaseScanID!)
        check(Set(actualFindings.map(\.id)) == Set(expected.findings!.map(\.id)))
        for reason in Set(actualFindings.map(\.reason)) {
            let subset = try store.findings(scanID: first.databaseScanID!, reason: reason)
            check(Set(subset.map(\.id)) == Set(actualFindings.filter { $0.reason == reason }.map(\.id)))
        }
        print("Exact health-issue subset queries passed for imported and scanned reports.")
        check(first.health!.sorted { $0.name < $1.name } == expected.health!.sorted { $0.name < $1.name })
        func versionIDs(_ dbURL: URL) throws -> [String:Int64] {
            let connection = try SQLiteConnection(dbURL)
            var result: [String:Int64] = [:]
            try connection.rows("SELECT path,id FROM record_versions") { result[$0[0].string] = $0[1].int }
            return result
        }
        let beforeIDs = try versionIDs(store.url)
        let reused = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(reused.reusedRecords == 100 && reused.tracks == 100)
        check(try versionIDs(store.url) == beforeIDs)
        check(try store.integrityCheck())

        let cancelMidway = JobCancellation()
        let cancelled = try? await LibraryScanner.scan(root, previous: nil, reuse: false, includeAudio: false, store: store, cancellation: cancelMidway) { if $0.done >= 21 { cancelMidway.cancel() } }
        check(cancelled == nil)
        check(try store.snapshot(root: root.path)?.databaseScanID == reused.databaseScanID)
        let dbURL = store.url
        store = try LibraryStore(url: dbURL)
        let resumed = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(resumed.reusedRecords == 100 && resumed.tracks == 100)
        check(try store.records(scanID: resumed.databaseScanID!).count == 100)
        print("SQL scan reuse, immutable-record reuse, aggregate/health parity, checkpoint persistence and last-complete preservation checks passed.")

        let freshRoot = base.appendingPathComponent("No Completed Snapshot")
        try fm.createDirectory(at: freshRoot, withIntermediateDirectories: true)
        for i in 0..<30 { try ID3(audio).writing(Tags(title: "Fresh \(i)", artist: "Artist"), original: audio).write(to: freshRoot.appendingPathComponent("\(i).mp3")) }
        let freshCancel = JobCancellation()
        _ = try? await LibraryScanner.scan(freshRoot, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: freshCancel) { if $0.done >= 11 { freshCancel.cancel() } }
        check(try store.snapshot(root: freshRoot.path) == nil)
        let freshResume = try await LibraryScanner.scan(freshRoot, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(freshResume.reusedRecords == 11 && freshResume.tracks == 30)
        check(try store.snapshot(root: root.path)?.tracks == 100)

        try fm.removeItem(at: root.appendingPathComponent("1.mp3"))
        try ID3(audio).writing(Tags(title: "Changed", artist: "Artist"), original: audio).write(to: root.appendingPathComponent("0.mp3"))
        try ID3(audio).writing(Tags(title: "New", artist: "Artist"), original: audio).write(to: root.appendingPathComponent("new.mp3"))
        let updated = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(updated.tracks == 100 && updated.reusedRecords == 98)
        let updatedRecords = try store.records(scanID: updated.databaseScanID!)
        check(updatedRecords.contains { $0.path.hasSuffix("/0.mp3") && $0.tags.title == "Changed" })
        check(!updatedRecords.contains { $0.path.hasSuffix("/1.mp3") })
        check((try? store.records(scanID: first.databaseScanID!)) == nil)
        let forced = try await LibraryScanner.scan(root, previous: nil, reuse: false, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(forced.reusedRecords == 0)
        do {
            let connection = try SQLiteConnection(store.url)
            try connection.execute("CREATE TRIGGER block_finish BEFORE UPDATE OF status ON scans WHEN NEW.status='complete' BEGIN SELECT RAISE(ABORT, 'synthetic commit failure'); END;")
        }
        check((try? await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }) == nil)
        check(try store.snapshot(root: root.path)?.databaseScanID == forced.databaseScanID)
        do { let connection = try SQLiteConnection(store.url); try connection.execute("DROP TRIGGER block_finish") }
        let afterRollback = try await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(afterRollback.reusedRecords == 100 && afterRollback.tracks == 100)
        var lease: StatisticsScanLease? = try store.acquireScanLease()
        check(lease != nil)
        check((try? await LibraryScanner.scan(root, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }) == nil)
        lease = nil
        check(try store.integrityCheck())
        print("SQL first-scan resume, separate-library reports, changed/deleted/new files, forced reread and exclusive scan lease checks passed.")

        let namingRoot = base.appendingPathComponent("Naming")
        let namingRecords = ["DJ Earworm", "Dj Earworm", "Dj Earworm"].enumerated().map { index, artist in
            LibraryRecord(path: namingRoot.appendingPathComponent("\(index).mp3").path, bytes: 1, tags: Tags(artist: artist), hasArtwork: false)
        }
        var namingRules = CleanRules(); namingRules.exceptions = "DJ"
        let namingSession = try store.start(root: namingRoot.path, includeAudio: false)
        try store.checkpoint(namingRecords.map { StoredLibraryRecord(record: $0, versionID: nil) }, root: namingRoot.path, session: namingSession)
        let namingSnapshot = try store.complete(root: namingRoot.path, session: namingSession, includeAudio: false, reused: 0, rules: namingRules, cancellation: cancel)
        let variations = try store.findings(scanID: namingSnapshot.databaseScanID!, reason: TagQuality.artistVariationReason)
        check(variations.count == 2 && variations.allSatisfy { $0.original == "Dj Earworm" && $0.suggestion == "DJ Earworm" })
        check(namingSnapshot.health?.contains { $0.name == "Artist naming variations" && $0.tracks == 2 } == true)
        print("SQLite artist naming suggestions honor Clean Rules exceptions over frequency.")

        let linkedRoot = base.appendingPathComponent("Links")
        try fm.createDirectory(at: linkedRoot, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkedRoot.appendingPathComponent("Linked Folder"), withDestinationURL: root)
        try fm.createSymbolicLink(at: linkedRoot.appendingPathComponent("linked.mp3"), withDestinationURL: root.appendingPathComponent("0.mp3"))
        let linksSnapshot = try await LibraryScanner.scan(linkedRoot, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
        check(linksSnapshot.tracks == 0 && linksSnapshot.skippedSymbolicLinks == 2)
        check(try store.snapshot(root: linkedRoot.path)?.skippedSymbolicLinks == 2)
        print("Statistics skips and reports linked files/folders, retaining the skipped count in SQLite.")

        let fixture = URL(fileURLWithPath: "work/audio-fixture.mp3")
        if fm.fileExists(atPath: fixture.path) {
            let audioRoot = base.appendingPathComponent("Real Audio")
            try fm.createDirectory(at: audioRoot, withIntermediateDirectories: true)
            try fm.copyItem(at: fixture, to: audioRoot.appendingPathComponent("Silence.mp3"))
            let noAudio = try await LibraryScanner.scan(audioRoot, previous: nil, reuse: true, includeAudio: false, store: store, cancellation: cancel) { _ in }
            check(noAudio.durationSeconds == nil)
            let withAudio = try await LibraryScanner.scan(audioRoot, previous: nil, reuse: true, includeAudio: true, store: store, cancellation: cancel) { _ in }
            check((withAudio.durationSeconds ?? 0) > 0 && withAudio.reusedRecords == 1)
            let audioAgain = try await LibraryScanner.scan(audioRoot, previous: nil, reuse: true, includeAudio: true, store: store, cancellation: cancel) { _ in }
            check(audioAgain.durationSeconds == withAudio.durationSeconds && audioAgain.reusedRecords == 1)
            check(try store.records(scanID: audioAgain.databaseScanID!).first?.audioRead == true)
            print("SQLite optional audio enrichment and reuse checks passed with real MP3 audio.")
        }
    }
}
