import Foundation
import AVFoundation
import CoreMedia

struct LibraryRecord: Codable, Equatable {
    var path: String
    var bytes: Int64
    var modified: Date?
    var tags: Tags
    var hasArtwork: Bool
    var error: String?
    var duration: Double?
    var bitrate: Int?
    var sampleRate: Int?
    var audioRead: Bool = false
}
struct ScanProgress {
    var done: Int
    var total: Int
    var reused: Int
    var elapsed: Double
    var skippedLinks = 0
    static func count(_ value: Int) -> String { value.formatted(.number.locale(Locale(identifier: "en_US"))) }
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let total = Int(max(0, min(seconds, 359_999_999)))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
    var text: String {
        let skipped = skippedLinks > 0 ? " · \(Self.count(skippedLinks)) symbolic links skipped" : ""
        let pending = "Processing rate and estimated time are being calculated…"
        if done == 0 {
            return "Discovering library files · \(Self.count(total)) found · \(Self.duration(elapsed)) elapsed · " + pending + skipped
        }
        let prefix = "\(Self.count(done)) of \(Self.count(total)) tracks · \(Self.count(reused)) reused · \(Self.duration(elapsed)) elapsed · "
        guard done >= 10, elapsed > 0 else { return prefix + pending }
        let rate = Double(done) / elapsed
        return prefix + "Avg. processing rate: \(rate.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(1)))) tracks/sec · ~\(Self.duration(Double(max(0, total - done)) / rate)) remaining" + skipped
    }
}
struct LibraryScanner {
    static func scan(_ root: URL, previous: LibrarySnapshot?, reuse: Bool, includeAudio: Bool, store: LibraryStore? = nil, rules: CleanRules = CleanRules(), cancellation: JobCancellation, progress: (ScanProgress) -> Void) async throws -> LibrarySnapshot {
        try SymbolicLinks.validate(root)
        let lease = try store?.acquireScanLease()
        defer { withExtendedLifetime(lease) {} }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw TagError(message: "Library folder is unavailable.") }
        let started = Date()
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return true }) else { throw TagError(message: "Cannot enumerate library.") }
        var urls: [URL] = [], skippedLinks = 0
        while let url = enumerator.nextObject() as? URL {
            try cancellation.check()
            if SymbolicLinks.isLink(url) { skippedLinks += 1; continue }
            if url.pathExtension.lowercased() == "mp3", (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { urls.append(url) }
            if urls.count % 250 == 0 { progress(.init(done: 0, total: urls.count, reused: 0, elapsed: Date().timeIntervalSince(started), skippedLinks: skippedLinks)) }
        }
        if let error = enumerationError { throw TagError(message: "Incomplete library scan; previous snapshot retained. " + error.localizedDescription) }
        let session = try store?.start(root: root.path, includeAudio: includeAudio)
        let cached = Dictionary((previous?.root == root.path ? previous?.records ?? [] : []).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var records: [LibraryRecord] = [], reused = 0
        var checkpoint: [StoredLibraryRecord] = []
        do {
        for (index, url) in urls.enumerated() {
            try cancellation.check()
            let stamp = FileJobs.fingerprint(url)
            guard let bytes = stamp.0, let modified = stamp.1 else { throw TagError(message: "File disappeared during scan: " + url.path) }
            var record: LibraryRecord
            var versionID: Int64?
            let stored = reuse && session != nil ? try store?.cached(root: root.path, session: session!, path: url.path, bytes: Int64(bytes), modified: modified, includeAudio: includeAudio) : nil
            if let stored {
                record = stored.record; versionID = stored.versionID; reused += 1
            } else if store == nil, reuse, let old = cached[url.path], old.bytes == Int64(bytes), old.modified == modified, old.error == nil {
                record = old; reused += 1
            } else {
                do {
                    let parsed = try ID3(Data(contentsOf: url, options: .mappedIfSafe))
                    record = .init(path: url.path, bytes: Int64(bytes), modified: modified, tags: parsed.tags, hasArtwork: parsed.artworkData != nil)
                } catch { record = .init(path: url.path, bytes: Int64(bytes), modified: modified, tags: Tags(), hasArtwork: false, error: error.localizedDescription) }
            }
            if includeAudio && (!record.audioRead || record.duration == nil) {
                versionID = nil
                do {
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration >= 0, let track = try await asset.loadTracks(withMediaType: .audio).first else { throw TagError(message: "Audio details unavailable") }
                    let rate = try await track.load(.estimatedDataRate)
                    let formats = try await track.load(.formatDescriptions)
                    let sample = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 0
                    record.duration = duration
                    record.bitrate = rate > 0 ? Int((rate / 1000).rounded()) : nil
                    record.sampleRate = sample > 0 ? Int(sample) : nil
                    record.audioRead = true
                } catch { record.audioRead = true; record.duration = nil }
            }
            let after = FileJobs.fingerprint(url)
            guard after.0 == stamp.0, after.1 == stamp.1 else { throw TagError(message: "File changed during statistics update; previous snapshot retained. " + url.path) }
            if let store, let session {
                checkpoint.append(.init(record: record, versionID: versionID))
                if checkpoint.count >= 50 { try store.checkpoint(checkpoint, root: root.path, session: session); checkpoint.removeAll(keepingCapacity: true) }
            } else { records.append(record) }
            if index % 10 == 0 || index + 1 == urls.count { progress(.init(done: index + 1, total: urls.count, reused: reused, elapsed: Date().timeIntervalSince(started), skippedLinks: skippedLinks)) }
        }
        try cancellation.check()
        if let store, let session {
            try store.checkpoint(checkpoint, root: root.path, session: session); checkpoint.removeAll()
            return try store.complete(root: root.path, session: session, includeAudio: includeAudio, reused: reused, rules: rules, skippedLinks: skippedLinks, cancellation: cancellation)
        }
        var result = summarize(root, records: records, includeAudio: includeAudio, reused: reused, rules: rules)
        result.skippedSymbolicLinks = skippedLinks
        return result
        } catch {
            // Cache completed reads, but never change the last completed report on failure/cancel.
            if let store, let session, !checkpoint.isEmpty { try? store.checkpoint(checkpoint, root: root.path, session: session) }
            throw error
        }
    }
    static func summarize(_ root: URL, records: [LibraryRecord], includeAudio: Bool, reused: Int = 0, rules: CleanRules = CleanRules()) -> LibrarySnapshot {
        var result = LibrarySnapshot(root: root.path, updated: Date())
        result.records = records; result.reusedRecords = reused
        result.tracks = records.count; result.bytes = records.reduce(0) { $0 + $1.bytes }; result.unreadable = records.filter { $0.error != nil }.count
        func groups(_ key: (LibraryRecord) -> String) -> [LibraryGroup] {
            Dictionary(grouping: records, by: { key($0).trimmingCharacters(in: .whitespacesAndNewlines) }).map { name, rows in
                LibraryGroup(name: name.isEmpty ? "Unknown" : name, tracks: rows.count, bytes: rows.reduce(0) { $0 + $1.bytes })
            }.sorted { $0.tracks == $1.tracks ? $0.name < $1.name : $0.tracks > $1.tracks }
        }
        result.artists = groups { $0.tags.artist }; result.genres = groups { $0.tags.genre }; result.years = groups { $0.tags.year }
        result.albumCount = Set(records.filter { !$0.tags.album.isEmpty }.map { ($0.tags.albumArtist.isEmpty ? $0.tags.artist : $0.tags.albumArtist) + "\u{1f}" + $0.tags.album }).count
        var findings = records.filter { $0.error == nil }.flatMap { TagQuality.findings(path: $0.path, tags: $0.tags, artwork: $0.hasArtwork) }
        findings += TagQuality.consistency(records.filter { $0.error == nil }, rules: rules)
        for record in records {
            if let error = record.error { findings.append(.init(path: record.path, field: "Read Error", reason: error)) }
            if includeAudio, let rate = record.bitrate, rate < 192 { findings.append(.init(path: record.path, field: "Bitrate", reason: "Estimated bitrate below 192 kbps")) }
        }
        result.findings = findings
        result.health = Dictionary(grouping: findings, by: { $0.reason }).map { name, rows in LibraryGroup(name: name, tracks: Set(rows.map(\.path)).count) }.sorted { $0.tracks > $1.tracks }
        if includeAudio {
            result.durationSeconds = records.compactMap(\.duration).reduce(0, +)
            result.audioDetailsUnreadable = records.filter { $0.duration == nil }.count
            result.bitrates = groups { $0.bitrate.map { "\($0) kbps" } ?? "Unknown" }
            result.sampleRates = groups { $0.sampleRate.map { "\($0) Hz" } ?? "Unknown" }
        }
        return result
    }
}
