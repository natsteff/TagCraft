import Foundation
import Darwin

struct StoredLibraryRecord {
    var record: LibraryRecord
    var versionID: Int64?
}
struct LibraryScanSession {
    var id: Int64
    var token: String
    var resumed: Bool
}
/// A single serialized connection. No lock is held across an async suspension.
final class LibraryStore: @unchecked Sendable {
    let url: URL
    private let db: SQLiteConnection
    private let lock = NSRecursiveLock()
    init(url: URL) throws {
        self.url = url
        db = try SQLiteConnection(url)
        let version = try db.first("PRAGMA user_version")?.first?.int ?? 0
        guard version <= 1 else { throw TagError(message: "Statistics database was created by a newer app. It has been left untouched.") }
        try db.execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        if version == 0 {
            try db.transaction {
                try db.execute("""
                CREATE TABLE libraries(root TEXT PRIMARY KEY, current_scan INTEGER);
                CREATE TABLE scans(id INTEGER PRIMARY KEY, root TEXT NOT NULL REFERENCES libraries(root), status TEXT NOT NULL CHECK(status IN ('working','complete')), started REAL NOT NULL, finished REAL, include_audio INTEGER NOT NULL, legacy_findings INTEGER NOT NULL DEFAULT 0, summary BLOB);
                CREATE INDEX scans_root_status ON scans(root,status);
                CREATE TABLE record_versions(id INTEGER PRIMARY KEY, root TEXT NOT NULL REFERENCES libraries(root), path TEXT NOT NULL, bytes INTEGER NOT NULL, modified REAL, artist TEXT NOT NULL, title TEXT NOT NULL, album TEXT NOT NULL, album_artist TEXT NOT NULL, genre TEXT NOT NULL, year TEXT NOT NULL, track TEXT NOT NULL, extra BLOB NOT NULL, artwork INTEGER NOT NULL, error TEXT, duration REAL, bitrate INTEGER, sample_rate INTEGER, audio_read INTEGER NOT NULL, artist_key TEXT NOT NULL, folder TEXT NOT NULL, album_key TEXT NOT NULL);
                CREATE INDEX records_identity ON record_versions(root,path,bytes,modified);
                CREATE INDEX records_artist ON record_versions(root,artist_key,artist);
                CREATE INDEX records_album ON record_versions(root,folder,album_key);
                CREATE TABLE scan_files(scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE, path TEXT NOT NULL, version_id INTEGER NOT NULL REFERENCES record_versions(id), seen TEXT NOT NULL, PRIMARY KEY(scan_id,path));
                CREATE INDEX scan_files_version ON scan_files(version_id);
                CREATE TABLE record_findings(record_id INTEGER NOT NULL REFERENCES record_versions(id) ON DELETE CASCADE, field TEXT NOT NULL, reason TEXT NOT NULL, suggestion TEXT, original TEXT, PRIMARY KEY(record_id,field,reason));
                CREATE TABLE scan_findings(scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE, path TEXT NOT NULL, field TEXT NOT NULL, reason TEXT NOT NULL, suggestion TEXT, original TEXT, PRIMARY KEY(scan_id,path,field,reason));
                CREATE INDEX scan_findings_reason ON scan_findings(scan_id,reason,path);
                PRAGMA user_version=1;
                """)
            }
        }
        try db.execute("CREATE INDEX IF NOT EXISTS record_findings_reason ON record_findings(reason,record_id);")
    }
    private func access<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    private let columns = "r.path,r.bytes,r.modified,r.artist,r.title,r.album,r.album_artist,r.genre,r.year,r.track,r.extra,r.artwork,r.error,r.duration,r.bitrate,r.sample_rate,r.audio_read"
    private func record(_ values: [SQLValue]) throws -> LibraryRecord {
        guard let extra = values[10].data else { throw TagError(message: "Statistics database record is incomplete.") }
        let tags = Tags(extra: try JSONDecoder().decode([String:String].self, from: extra), title: values[4].string, artist: values[3].string, album: values[5].string, albumArtist: values[6].string, year: values[8].string, genre: values[7].string, track: values[9].string)
        return .init(path: values[0].string, bytes: values[1].int, modified: values[2].double.map(Date.init(timeIntervalSinceReferenceDate:)), tags: tags, hasArtwork: values[11].int != 0, error: values[12].optionalString, duration: values[13].double, bitrate: values[14].double.map(Int.init), sampleRate: values[15].double.map(Int.init), audioRead: values[16].int != 0)
    }
    func snapshot(root: String? = nil) throws -> LibrarySnapshot? {
        try access {
            let row = try db.first("SELECT s.id,s.summary FROM libraries l JOIN scans s ON s.id=l.current_scan WHERE s.status='complete'" + (root == nil ? " ORDER BY s.finished DESC LIMIT 1" : " AND l.root=? LIMIT 1"), root.map { [.text($0)] } ?? [])
            guard let row, let data = row[1].data else { return nil }
            var summary = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            summary.records = nil; summary.findings = nil
            summary.databaseBacked = true; summary.databaseScanID = row[0].int
            return summary
        }
    }
    func start(root: String, includeAudio: Bool) throws -> LibraryScanSession {
        try access {
            try db.transaction {
                try db.run("INSERT OR IGNORE INTO libraries(root) VALUES(?)", [.text(root)])
                if let row = try db.first("SELECT id FROM scans WHERE root=? AND status='working' ORDER BY id DESC LIMIT 1", [.text(root)]) {
                    try db.run("UPDATE scans SET include_audio=? WHERE id=?", [.integer(includeAudio ? 1 : 0), row[0]])
                    return .init(id: row[0].int, token: UUID().uuidString, resumed: true)
                }
                try db.run("INSERT INTO scans(root,status,started,include_audio) VALUES(?,'working',?,?)", [.text(root), .real(Date().timeIntervalSinceReferenceDate), .integer(includeAudio ? 1 : 0)])
                return .init(id: db.insertedID, token: UUID().uuidString, resumed: false)
            }
        }
    }
    func cached(root: String, session: LibraryScanSession, path: String, bytes: Int64, modified: Date, includeAudio: Bool) throws -> StoredLibraryRecord? {
        try access {
            let row = try db.first("""
                SELECT \(columns),r.id FROM scan_files f JOIN record_versions r ON r.id=f.version_id
                WHERE f.path=? AND (f.scan_id=? OR f.scan_id=(SELECT current_scan FROM libraries WHERE root=?))
                AND r.root=? AND r.bytes=? AND r.modified=? AND r.error IS NULL
                ORDER BY \(includeAudio ? "(r.audio_read=1 AND r.duration IS NOT NULL) DESC," : "") (f.scan_id=?) DESC LIMIT 1
                """, [.text(path), .integer(session.id), .text(root), .text(root), .integer(bytes), .real(modified.timeIntervalSinceReferenceDate), .integer(session.id)])
            guard let row else { return nil }
            return .init(record: try record(row), versionID: row[17].int)
        }
    }
    private func insert(_ value: LibraryRecord, root: String) throws -> Int64 {
        let tags = value.tags
        try db.run("""
            INSERT INTO record_versions(root,path,bytes,modified,artist,title,album,album_artist,genre,year,track,extra,artwork,error,duration,bitrate,sample_rate,audio_read,artist_key,folder,album_key)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, [.text(root), .text(value.path), .integer(value.bytes), .optional(value.modified?.timeIntervalSinceReferenceDate), .text(tags.artist), .text(tags.title), .text(tags.album), .text(tags.albumArtist), .text(tags.genre), .text(tags.year), .text(tags.track), .blob(try JSONEncoder().encode(tags.extra)), .integer(value.hasArtwork ? 1 : 0), .optional(value.error), .optional(value.duration), .optional(value.bitrate), .optional(value.sampleRate), .integer(value.audioRead ? 1 : 0), .text(LibraryTools.normalized(tags.artist)), .text(URL(fileURLWithPath: value.path).deletingLastPathComponent().path), .text(tags.album.lowercased())])
        let id = db.insertedID
        let findings = value.error.map { [QualityFinding(path: value.path, field: "Read Error", reason: $0)] } ?? TagQuality.findings(path: value.path, tags: tags, artwork: value.hasArtwork)
        for finding in findings {
            try db.run("INSERT INTO record_findings(record_id,field,reason,suggestion,original) VALUES(?,?,?,?,?)", [.integer(id), .text(finding.field), .text(finding.reason), .optional(finding.suggestion), .optional(finding.original)])
        }
        return id
    }
    func checkpoint(_ values: [StoredLibraryRecord], root: String, session: LibraryScanSession) throws {
        try access {
            try db.transaction {
                for value in values {
                    let id = try value.versionID ?? insert(value.record, root: root)
                    try db.run("INSERT INTO scan_files(scan_id,path,version_id,seen) VALUES(?,?,?,?) ON CONFLICT(scan_id,path) DO UPDATE SET version_id=excluded.version_id,seen=excluded.seen", [.integer(session.id), .text(value.record.path), .integer(id), .text(session.token)])
                }
            }
        }
    }
    private func findingQuery(_ id: Int64) throws -> String {
        guard let scan = try db.first("SELECT include_audio,legacy_findings FROM scans WHERE id=?", [.integer(id)]) else { throw TagError(message: "Statistics snapshot is no longer available. Reopen the report.") }
        let global = "SELECT path,field,reason,suggestion,original FROM scan_findings WHERE scan_id=\(id)"
        if scan[1].int == 1 { return global }
        var query = "SELECT f.path,q.field,q.reason,q.suggestion,q.original FROM scan_files f JOIN record_findings q ON q.record_id=f.version_id WHERE f.scan_id=\(id) UNION ALL " + global
        if scan[0].int != 0 { query += " UNION ALL SELECT f.path,'Bitrate','Estimated bitrate below 192 kbps',NULL,NULL FROM scan_files f JOIN record_versions r ON r.id=f.version_id WHERE f.scan_id=\(id) AND r.bitrate < 192" }
        return query
    }
    private func consistency(_ id: Int64, rules: CleanRules) throws {
        try db.run("DELETE FROM scan_findings WHERE scan_id=?", [.integer(id)])
        let base = "SELECT r.* FROM scan_files f JOIN record_versions r ON r.id=f.version_id WHERE f.scan_id=\(id) AND r.error IS NULL"
        var keys: [String] = []
        try db.rows("SELECT artist_key FROM (\(base)) WHERE artist_key<>'' GROUP BY artist_key HAVING COUNT(DISTINCT artist)>1") { keys.append($0[0].string) }
        for key in keys {
            var counts: [String: Int] = [:]
            try db.rows("SELECT artist,COUNT(*) FROM (\(base)) WHERE artist_key=? GROUP BY artist", [.text(key)]) { counts[$0[0].string] = Int($0[1].int) }
            guard let preferred = TagQuality.preferredArtist(counts, rules: rules) else { continue }
            try db.run("INSERT INTO scan_findings(scan_id,path,field,reason,suggestion,original) SELECT ?,path,'Artist','Artist naming variations',?,artist FROM (\(base)) WHERE artist_key=? AND artist<>?", [.integer(id), .text(preferred), .text(key), .text(preferred)])
        }
        try db.run("""
            WITH rows AS (\(base)), conflicts AS (
                SELECT folder,album_key,COUNT(DISTINCT NULLIF(album_artist,'')) AS nonempty,MAX(NULLIF(album_artist,'')) AS preferred
                FROM rows WHERE album_key<>'' GROUP BY folder,album_key HAVING COUNT(DISTINCT album_artist)>1
            )
            INSERT INTO scan_findings(scan_id,path,field,reason,suggestion,original)
            SELECT ?,r.path,'Album Artist','Inconsistent album artist within this album folder',CASE WHEN r.album_artist='' AND c.nonempty=1 THEN c.preferred ELSE NULL END,r.album_artist
            FROM rows r JOIN conflicts c ON r.folder=c.folder AND r.album_key=c.album_key
            """, [.integer(id)])
    }
    private func groups(_ id: Int64, expression: String, name: String? = nil) throws -> [LibraryGroup] {
        var result: [LibraryGroup] = []
        try db.rows("SELECT \(expression) AS name,COUNT(*),COALESCE(SUM(r.bytes),0) FROM scan_files f JOIN record_versions r ON r.id=f.version_id WHERE f.scan_id=? GROUP BY name ORDER BY COUNT(*) DESC,name ASC", [.integer(id)]) {
            result.append(.init(name: $0[0].string, tracks: Int($0[1].int), bytes: $0[2].int))
        }
        return result
    }
    private func summary(root: String, id: Int64, includeAudio: Bool, reused: Int) throws -> LibrarySnapshot {
        var result = LibrarySnapshot(root: root, updated: Date())
        let totals = try db.first("SELECT COUNT(*),COALESCE(SUM(r.bytes),0),COALESCE(SUM(r.error IS NOT NULL),0),COALESCE(SUM(r.duration),0),COALESCE(SUM(r.duration IS NULL),0) FROM scan_files f JOIN record_versions r ON r.id=f.version_id WHERE f.scan_id=?", [.integer(id)])!
        result.tracks = Int(totals[0].int); result.bytes = totals[1].int; result.unreadable = Int(totals[2].int); result.reusedRecords = reused
        func tag(_ name: String) -> String { "CASE WHEN tagcraft_trim(r.\(name))='' THEN 'Unknown' ELSE tagcraft_trim(r.\(name)) END" }
        result.artists = try groups(id, expression: tag("artist")); result.genres = try groups(id, expression: tag("genre")); result.years = try groups(id, expression: tag("year"))
        result.albumCount = Int(try db.first("SELECT COUNT(*) FROM (SELECT r.album,CASE WHEN r.album_artist='' THEN r.artist ELSE r.album_artist END FROM scan_files f JOIN record_versions r ON r.id=f.version_id WHERE f.scan_id=? AND r.album<>'' GROUP BY 1,2)", [.integer(id)])!.first!.int)
        if includeAudio {
            result.durationSeconds = totals[3].double; result.audioDetailsUnreadable = Int(totals[4].int)
            result.bitrates = try groups(id, expression: "CASE WHEN r.bitrate IS NULL THEN 'Unknown' ELSE CAST(r.bitrate AS TEXT)||' kbps' END")
            result.sampleRates = try groups(id, expression: "CASE WHEN r.sample_rate IS NULL THEN 'Unknown' ELSE CAST(r.sample_rate AS TEXT)||' Hz' END")
        }
        var health: [LibraryGroup] = []
        try db.rows("SELECT reason,COUNT(DISTINCT path) FROM (\(findingQuery(id))) GROUP BY reason ORDER BY COUNT(DISTINCT path) DESC,reason ASC") { health.append(.init(name: $0[0].string, tracks: Int($0[1].int))) }
        result.health = health
        return result
    }
    private func publish(_ snapshot: LibrarySnapshot, session: LibraryScanSession) throws {
        var summary = snapshot; summary.records = nil; summary.findings = nil; summary.databaseBacked = nil; summary.databaseScanID = nil
        try db.run("UPDATE scans SET status='complete',finished=?,summary=? WHERE id=?", [.real(snapshot.updated.timeIntervalSinceReferenceDate), .blob(try JSONEncoder().encode(summary)), .integer(session.id)])
        try db.run("UPDATE libraries SET current_scan=? WHERE root=?", [.integer(session.id), .text(snapshot.root)])
        try db.run("DELETE FROM scans WHERE root=? AND id<>? AND status='complete'", [.text(snapshot.root), .integer(session.id)])
        try db.run("DELETE FROM record_versions WHERE root=? AND NOT EXISTS(SELECT 1 FROM scan_files f WHERE f.version_id=record_versions.id)", [.text(snapshot.root)])
    }
    func complete(root: String, session: LibraryScanSession, includeAudio: Bool, reused: Int, rules: CleanRules = CleanRules(), skippedLinks: Int = 0, cancellation: JobCancellation) throws -> LibrarySnapshot {
        try access {
            try db.withCancellation(cancellation) {
                try db.transaction {
                    try db.run("DELETE FROM scan_files WHERE scan_id=? AND seen<>?", [.integer(session.id), .text(session.token)])
                    try consistency(session.id, rules: rules)
                    var result = try summary(root: root, id: session.id, includeAudio: includeAudio, reused: reused)
                    result.skippedSymbolicLinks = skippedLinks
                    try cancellation.check(); try publish(result, session: session)
                }
            }
            return try snapshot(root: root)!
        }
    }
    func records(scanID: Int64, cancellation: JobCancellation? = nil) throws -> [LibraryRecord] {
        try access {
            guard try db.first("SELECT id FROM scans WHERE id=? AND status='complete'", [.integer(scanID)]) != nil else { throw TagError(message: "Statistics changed. Reopen Library Statistics before exporting.") }
            var values: [LibraryRecord] = []
            try db.rows("SELECT \(columns) FROM scan_files f JOIN record_versions r ON r.id=f.version_id WHERE f.scan_id=? ORDER BY f.path", [.integer(scanID)]) { try cancellation?.check(); values.append(try record($0)) }
            return values
        }
    }
    func findings(scanID: Int64, reason: String? = nil, cancellation: JobCancellation? = nil) throws -> [QualityFinding] {
        try access {
            var result: [QualityFinding] = []
            let filter = reason == nil ? "" : " WHERE reason=?"
            try db.rows("SELECT path,field,reason,suggestion,original FROM (\(findingQuery(scanID)))" + filter + " ORDER BY path,field,reason", reason.map { [.text($0)] } ?? []) {
                try cancellation?.check(); result.append(.init(path: $0[0].string, field: $0[1].string, reason: $0[2].string, suggestion: $0[3].optionalString, original: $0[4].optionalString))
            }
            return result
        }
    }
    /// Used only by the one-time legacy importer, inside its unpublished temporary database.
    func importLegacy(_ snapshot: LibrarySnapshot) throws {
        try access {
            guard let records = snapshot.records, records.count == snapshot.tracks,
                  records.reduce(Int64(0), { $0 + $1.bytes }) == snapshot.bytes,
                  Set(records.map(\.path)).count == records.count else { throw TagError(message: "Legacy statistics are inconsistent; JSON was retained unchanged.") }
            try db.transaction {
                let session = try start(root: snapshot.root, includeAudio: snapshot.durationSeconds != nil)
                try checkpoint(records.map { .init(record: $0) }, root: snapshot.root, session: session)
                try db.run("UPDATE scans SET legacy_findings=1 WHERE id=?", [.integer(session.id)])
                for finding in snapshot.findings ?? [] {
                    try db.run("INSERT INTO scan_findings(scan_id,path,field,reason,suggestion,original) VALUES(?,?,?,?,?,?)", [.integer(session.id), .text(finding.path), .text(finding.field), .text(finding.reason), .optional(finding.suggestion), .optional(finding.original)])
                }
                try publish(snapshot, session: session)
                let imported = try self.records(scanID: session.id)
                guard Dictionary(uniqueKeysWithValues: imported.map { ($0.path, $0) }) == Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0) }),
                      try findings(scanID: session.id).count == snapshot.findings?.count ?? 0,
                      let saved = try self.snapshot(root: snapshot.root), saved.tracks == snapshot.tracks, saved.bytes == snapshot.bytes,
                      saved.artists == snapshot.artists, saved.genres == snapshot.genres, saved.years == snapshot.years, saved.health == snapshot.health else { throw TagError(message: "SQLite import verification failed; JSON was retained unchanged.") }
            }
        }
    }
    func closeForPublication() throws { try access { try db.closeForPublication() } }
    func integrityCheck() throws -> Bool { try access { try db.first("PRAGMA integrity_check")?.first?.string == "ok" } }
}

// A separate file-description lock protects a scan across awaits and across app processes.
// The lock file is retained so another process can never lock a replacement inode.
final class StatisticsScanLease: @unchecked Sendable {
    private let descriptor: Int32
    init(database: URL) throws {
        descriptor = Darwin.open(database.path + ".scan-lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TagError(message: "Cannot acquire statistics scan lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw TagError(message: "Another statistics scan is already using this database. Let it finish first.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
extension LibraryStore {
    func acquireScanLease() throws -> StatisticsScanLease { try StatisticsScanLease(database: url) }
}
