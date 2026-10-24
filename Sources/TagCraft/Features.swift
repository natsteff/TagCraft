import Foundation
import CryptoKit

struct CleanRules: Codable, Equatable {
    var whitespace = true
    var underscores = true
    var dots = true
    var capitalization = true
    var normalizeSeparators: Bool? = true
    // Legacy saved setting retained for decoding; Clean no longer removes track prefixes.
    var removeTrackPrefix = false
    var removeSuffixes = false
    var exceptions = "AC/DC\nR.E.M.\nABBA\nblink-182\nP!nk\nDJ\nEP\nUK\nUSA"
    var suffixes = "Official Video\nOfficial Music Video\nOfficial Audio\nLyrics\nLyric Video"
    func clean(_ filename: String, tags: Tags) throws -> (String, [String]) {
        let inputName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var explanations: [String] = []
        let dictionary = exceptions.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        func replace(_ value: String, _ pattern: String, _ template: String) -> String {
            value.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        func tidy(_ input: String, title: Bool) -> String {
            var value = input
            if removeSuffixes && title {
                let before = value
                let labels = suffixes.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                for _ in 0...labels.count {
                let previous = value
                for suffix in labels {
                    let escaped = NSRegularExpression.escapedPattern(for: suffix)
                    value = replace(value, "(?i)\\s*(?:[-–—]\\s*(?:[\\(\\[\\{]\\s*)?|[\\(\\[\\{]\\s*)" + escaped + "\\s*[\\)\\]\\}]?\\s*$", "")
                }
                if value == previous { break }
                }
                if value != before { explanations.append("Removed a configured suffix; Live/Remix/Acoustic are kept unless explicitly configured.") }
            }
            // Protect explicitly spelled artist/word exceptions from punctuation cleanup.
            var protected: [(String, String)] = []
            var protectedWords = dictionary
            for pattern in ["\\b(?:[\\p{L}]\\.)+[\\p{L}]\\.?", "\\d+\\.\\d+", "\\b(?:[A-Z]{1,3}-)+[A-Z]{1,3}\\b"] {
                let expression = try! NSRegularExpression(pattern: pattern)
                protectedWords += expression.matches(in: input, range: NSRange(input.startIndex..., in: input)).map { (input as NSString).substring(with: $0.range) }
            }
            for (index, word) in protectedWords.enumerated() {
                let marker = "ZZQEXCEPTION\(index)QZZ"
                let regex = try! NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])")
                let range = NSRange(value.startIndex..., in: value)
                if regex.firstMatch(in: value, range: range) != nil {
                    value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: marker)
                    let spelling = capitalization ? word : ((input.range(of: word, options: .caseInsensitive)).map { String(input[$0]) } ?? word)
                    protected.append((marker, spelling))
                }
            }
            if underscores { value = value.replacingOccurrences(of: "_", with: " ") }
            if normalizeSeparators ?? true {
            value = replace(value, "\\s*[-–—]\\s+|\\s+[-–—]\\s*", " - ")
            let beforeHyphens = value
            value = replace(value, "(?<=[\\p{L}])[-–—](?=[\\p{L}])", " - ")
            if value != beforeHyphens { explanations.append("Normalized an unspaced hyphen; review field boundaries before extracting tags.") }
            value = replace(value, "^(\\d{1,3}) +(?=[\\p{L}])", "$1 - ")
            }
            if dots {
                // Keep initials, decimal numbers and ellipses; replace word.separator dots.
                value = replace(value, "(?<=[\\p{L}\\p{N}])\\.(?=[\\p{L}\\p{N}])", " ")
            }
            if whitespace { value = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            if capitalization { value = value.capitalized(with: Locale(identifier: "en_US_POSIX")) }
            for (marker, spelling) in protected { value = value.replacingOccurrences(of: marker, with: spelling, options: .caseInsensitive) }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stem = LibraryPath.clean(tidy(inputName, title: true))
        guard !stem.isEmpty else { throw TagError(message: "Cleaning would leave an empty filename.") }
        let result = stem + ".mp3"
        if underscores { explanations.append("Replace underscores") }
        if dots { explanations.append("Clean separator dots; preserve configured names, initials and decimals") }
        if whitespace { explanations.append("Normalize spaces") }
        if capitalization { explanations.append("Title case with spelling exceptions") }
        return (result, explanations)
    }
}
struct WorkflowPreset: Codable, Identifiable {
    var id = UUID()
    var name = "Prepare Music"
    var clean = true
    var extract = true
    var purge = false
    var rename = true
    var move = false
    var cleanRules = CleanRules()
    var extractionMask = "{Artist} - {Title}"
    var renameMask = "{Artist} - {Title}"
    var ignoredGroups: Set<String> = []
    var purgeIDs: Set<String> = []
}
final class JobCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func check() throws { if isCancelled { throw CancellationError() } }
}
struct FilePlan {
    var source: URL
    var destination: URL
    var tags: Tags?
    var purge: Set<String> = []
    var artwork: Data?
    var removeArtwork = false
    var replaceAllArtwork = false
    var expectedSize: Int?
    var expectedDate: Date?
}
struct FileResult {
    var source: URL
    var destination: URL
    var tags: Tags?
    var error: String?
}
struct FileJobs {
    static func fingerprint(_ url: URL) -> (Int?, Date?) {
        // URL values can carry cached metadata across an undo/redo cycle.
        let freshURL = URL(fileURLWithPath: url.path)
        let resource = try? freshURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (resource?.fileSize, resource?.contentModificationDate)
    }
    static func run(_ plans: [FilePlan], cancellation: JobCancellation, progress: @escaping (Int, Int, String) -> Void) -> [FileResult] {
        var results: [FileResult] = []
        for (index, plan) in plans.enumerated() {
            if cancellation.isCancelled { break }
            progress(index, plans.count, plan.source.lastPathComponent)
            var rollbackBackup: URL?
            var mutated = false
            do {
                try SymbolicLinks.validate(plan.source)
                try SymbolicLinks.validate(plan.destination)
                let current = fingerprint(plan.source)
                if let size = plan.expectedSize, size != current.0 { throw TagError(message: "File changed since preview. Preview again.") }
                if let date = plan.expectedDate, date != current.1 { throw TagError(message: "File changed since preview. Preview again.") }
                let renamed = plan.source.standardizedFileURL.path != plan.destination.standardizedFileURL.path
                if renamed && destinationConflict(source: plan.source, destination: plan.destination) { throw TagError(message: "Destination already exists.") }
                let writes = plan.tags != nil || !plan.purge.isEmpty || plan.artwork != nil || plan.removeArtwork
                var updatedTags: Tags?
                if writes {
                    let original = try Data(contentsOf: plan.source, options: .mappedIfSafe)
                    let parsed = try ID3(original)
                    var updated = plan.tags.map { parsed.writing($0, original: original) } ?? original
                    if !plan.purge.isEmpty { updated = try ID3(updated).purging(plan.purge, original: updated) }
                    if plan.artwork != nil || plan.removeArtwork {
                        var id3 = try ID3(updated)
                        id3.frames.removeAll { $0.id == "APIC" && (plan.removeArtwork || plan.replaceAllArtwork || EmbeddedPicture.type($0) == 3) }
                        if let artwork = plan.artwork {
                            let mime = artwork.starts(with: [255,216]) ? "image/jpeg" : "image/png"
                            var payload = Data([0]); payload.append(Data(mime.utf8)); payload.append(contentsOf: [0,3,0]); payload.append(artwork)
                            id3.frames.append(.init(id: "APIC", payload: payload, flags: Data([0,0])))
                        }
                        updated = id3.writing(id3.tags, original: updated)
                    }
                    updatedTags = try ID3(updated).tags
                    try cancellation.check()
                    let backup = plan.source.deletingLastPathComponent().appendingPathComponent(".TagCraft Backups")
                    try SymbolicLinks.validate(backup)
                    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                    let backupFile = backup.appendingPathComponent(UUID().uuidString + "-" + plan.source.lastPathComponent)
                    try SymbolicLinks.validate(backupFile)
                    try original.write(to: backupFile, options: .atomic)
                    rollbackBackup = backupFile
                    // Complete a file once its first mutation begins; cancellation acts between files.
                    try SymbolicLinks.validate(plan.source)
                    try updated.write(to: plan.source, options: .atomic)
                    mutated = true
                }
                if renamed {
                    try SymbolicLinks.validate(plan.destination)
                    try FileManager.default.createDirectory(at: plan.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try rename(source: plan.source, destination: plan.destination)
                }
                results.append(.init(source: plan.source, destination: plan.destination, tags: updatedTags, error: nil))
            } catch {
                var reason = error.localizedDescription
                if mutated, let backup = rollbackBackup {
                    do { try SymbolicLinks.validate(plan.source); try Data(contentsOf: backup).write(to: plan.source, options: .atomic) }
                    catch { reason += " Rollback failed; restore the backup at " + backup.path }
                }
                results.append(.init(source: plan.source, destination: plan.source, tags: nil, error: reason))
            }
            progress(index + 1, plans.count, plan.source.lastPathComponent)
        }
        return results
    }
    static func hash(_ url: URL, audioOnly: Bool, cancellation: JobCancellation) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let size = try file.seekToEnd()
        var start: UInt64 = 0, end = size
        if audioOnly {
            try file.seek(toOffset: 0)
            let header = try file.read(upToCount: 10) ?? Data()
            if header.count == 10 && header.prefix(3) == Data("ID3".utf8) {
                start = UInt64(10 + ID3.sync(header.subdata(in: 6..<10)))
                if header[3] == 4 && header[5] & 16 != 0 { start += 10 }
            }
            if size >= 128 { try file.seek(toOffset: size - 128); if try file.read(upToCount: 3) == Data("TAG".utf8) { end -= 128 } }
        }
        guard start < end else { throw TagError(message: "No audio payload found.") }
        try file.seek(toOffset: start)
        var hash = SHA256(); var remaining = end - start
        while remaining > 0 {
            try cancellation.check()
            let chunk = try file.read(upToCount: Int(min(remaining, 1_048_576))) ?? Data()
            guard !chunk.isEmpty else { throw TagError(message: "File changed while hashing.") }
            hash.update(data: chunk); remaining -= UInt64(chunk.count)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
struct LibraryGroup: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var tracks = 0
    var bytes: Int64 = 0
}
struct LibrarySnapshot: Codable {
    var skippedSymbolicLinks: Int?
    var databaseBacked: Bool?
    var databaseScanID: Int64?
    var records: [LibraryRecord]?
    var findings: [QualityFinding]?
    var health: [LibraryGroup]?
    var reusedRecords: Int?
    var root: String
    var updated: Date
    var tracks = 0
    var bytes: Int64 = 0
    var unreadable = 0
    var albumCount: Int?
    var durationSeconds: Double?
    var audioDetailsUnreadable: Int?
    var bitrates: [LibraryGroup]?
    var sampleRates: [LibraryGroup]?
    var artists: [LibraryGroup] = []
    var genres: [LibraryGroup] = []
    var years: [LibraryGroup] = []
    var artistCount: Int { artists.filter { $0.name != "Unknown" }.count }
}
struct LibraryTools {
    static func statistics(_ root: URL, cancellation: JobCancellation, progress: (Int, String) -> Void) throws -> LibrarySnapshot {
        try SymbolicLinks.validate(root)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw TagError(message: "The library folder is unavailable.") }
        var enumerationError: Error?
        var snapshot = LibrarySnapshot(root: root.path, updated: Date())
        var albums = Set<String>()
        var artists: [String: LibraryGroup] = [:], genres: [String: LibraryGroup] = [:], years: [String: LibraryGroup] = [:]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey,.fileSizeKey], options: [.skipsHiddenFiles,.skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return true }) else { throw TagError(message: "Cannot read library folder.") }
        func add(_ input: String, _ bytes: Int64, _ values: inout [String: LibraryGroup]) {
            let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.isEmpty ? "Unknown" : name
            var group = values[key] ?? LibraryGroup(name: key)
            group.tracks += 1; group.bytes += bytes; values[key] = group
        }
        for case let url as URL in enumerator {
            try cancellation.check()
            if SymbolicLinks.isLink(url) { continue }
            guard url.pathExtension.lowercased() == "mp3" else { continue }
            guard let resource = try? url.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey]), resource.isRegularFile == true else { continue }
            let bytes = Int64(resource.fileSize ?? 0); snapshot.tracks += 1; snapshot.bytes += bytes
            let tags: Tags
            do { tags = try ID3(Data(contentsOf: url, options: .mappedIfSafe)).tags }
            catch { snapshot.unreadable += 1; tags = Tags() }
            if !tags.album.isEmpty { albums.insert(tags.artist + "\u{1f}" + tags.album) }
            add(tags.artist, bytes, &artists); add(tags.genre, bytes, &genres); add(tags.year, bytes, &years)
            if snapshot.tracks % 25 == 0 { progress(snapshot.tracks, url.lastPathComponent) }
        }
        try cancellation.check()
        if let error = enumerationError { throw TagError(message: "Statistics scan incomplete; previous snapshot kept. " + error.localizedDescription) }
        func sorted(_ values: [String: LibraryGroup]) -> [LibraryGroup] { values.values.sorted { $0.tracks == $1.tracks ? $0.name < $1.name : $0.tracks > $1.tracks } }
        snapshot.albumCount = albums.count
        snapshot.artists = sorted(artists); snapshot.genres = sorted(genres); snapshot.years = sorted(years)
        return snapshot
    }
    static func artistNames(_ root: URL, useLetterFolders: Bool = true, cancellation: JobCancellation? = nil) -> [String] {
        guard (try? SymbolicLinks.validate(root)) != nil else { return [] }
        var names = Set<String>()
        let fm = FileManager.default
        for bucket in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [] {
            if cancellation?.isCancelled == true { break }
            guard !SymbolicLinks.isLink(bucket), (try? bucket.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if !useLetterFolders { names.insert(bucket.lastPathComponent); continue }
            for artist in (try? fm.contentsOfDirectory(at: bucket, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [] {
                if cancellation?.isCancelled == true { break }
                if !SymbolicLinks.isLink(artist), (try? artist.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { names.insert(artist.lastPathComponent) }
            }
        }
        return names.sorted()
    }
    static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive,.caseInsensitive,.widthInsensitive], locale: .current).filter { $0.isLetter || $0.isNumber }
    }
    static func suggestions(_ artist: String, names: [String]) -> [String] {
        let key = normalized(artist)
        guard !key.isEmpty else { return [] }
        func distance(_ a: String, _ b: String) -> Int {
            let left = Array(a), right = Array(b); var previous = Array(0...right.count)
            for (i, x) in left.enumerated() {
                var row = [i + 1]
                for (j, y) in right.enumerated() { row.append(min(row[j]+1, previous[j+1]+1, previous[j]+(x == y ? 0 : 1))) }
                previous = row
            }
            return previous.last ?? 0
        }
        return names.filter { $0 != artist }.map { ($0, distance(key, normalized($0))) }
            .filter { $0.1 == 0 || (key.count >= 5 && $0.1 <= 1) }.sorted { $0.1 < $1.1 }.prefix(5).map(\.0)
    }
}
extension ID3 {
    var artworkData: Data? {
        let pictures = EmbeddedPicture.read(self)
        return pictures.first(where: { $0.type == 3 })?.data ?? pictures.first?.data
    }
}

struct SettingsFiles {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TagCraft Music Librarian", isDirectory: true)
    }
    static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch { /* Cache/preferences are optional; file operations don't rely on them. */ }
    }
}

struct PreparationInput {
    var url: URL
    var tags: Tags
    var issue: String?
}
struct PreparationPreview {
    var statusText: String? = nil
    var source: URL
    var plan: FilePlan?
    var detail: String
    var issue: String?
}
struct WorkflowPlanner {
    static func preview(_ inputs: [PreparationInput], preset: WorkflowPreset, library: URL?, structure: LibraryStructure = LibraryStructure(), cancellation: JobCancellation, progress: (Int, Int) -> Void) throws -> [PreparationPreview] {
        var destinations = Set<String>()
        var previews: [PreparationPreview] = []
        for (index, input) in inputs.enumerated() {
            try cancellation.check(); progress(index, inputs.count)
            do {
                if let issue = input.issue { throw TagError(message: issue) }
                var name = input.url.lastPathComponent
                var tags = input.tags
                var detail: [String] = []
                if preset.clean { let cleaned = try preset.cleanRules.clean(name, tags: tags); name = cleaned.0; detail += cleaned.1 }
                if preset.extract {
                    tags = try FilenameMask(preset.extractionMask, ignoredGroups: preset.ignoredGroups).extract(name, existing: tags)
                    detail.append("Extract tags using " + preset.extractionMask)
                }
                let tagsBeforePurge = tags
                let purge = preset.purge ? preset.purgeIDs : []
                if !purge.isEmpty {
                    let original = try Data(contentsOf: input.url, options: .mappedIfSafe)
                    let tagged = try ID3(original).writing(tags, original: original)
                    let parsed = try ID3(tagged)
                    tags = try ID3(parsed.purging(purge, original: tagged)).tags
                    detail.append("Purge " + purge.sorted().joined(separator: ", "))
                }
                if preset.rename { name = try FilenameTemplate(preset.renameMask).filename(tags: tags); detail.append("Rename from resulting tags") }
                var destination = input.url.deletingLastPathComponent().appendingPathComponent(name)
                if preset.move {
                    guard let library else { throw TagError(message: "Choose a library before using a move step.") }
                    destination = try LibraryPath.destination(root: library, artist: tags.artist, filename: name, album: tags.album, structure: structure)
                    detail.append("Move to " + destination.path)
                }
                let key = destination.path.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .current)
                guard destinations.insert(key).inserted else { throw TagError(message: "Two files would receive the same destination.") }
                if destination.path != input.url.path && FileJobs.destinationConflict(source: input.url, destination: destination) { throw TagError(message: "Destination exists.") }
                let stamp = FileJobs.fingerprint(input.url)
                let tagChanges = tags != input.tags
                var purgeChanges = false
                if !purge.isEmpty {
                    let original = try Data(contentsOf: input.url, options: .mappedIfSafe)
                    purgeChanges = try ID3(original).frames.contains { purge.contains($0.id) } || !ID3.legacyFields(original).intersection(purge).isEmpty
                }
                var changes: [String] = []
                if destination.lastPathComponent != input.url.lastPathComponent { changes.append("rename") }
                if destination.deletingLastPathComponent().path != input.url.deletingLastPathComponent().path { changes.append("move") }
                if tagChanges { changes.append("update tags") }
                if purgeChanges { changes.append("purge tags") }
                if changes.isEmpty {
                    previews.append(.init(source: input.url, plan: nil, detail: "Filename, tags and location already match the workflow.", issue: "No change needed."))
                    continue
                }
                let statusText = "Will " + changes.joined(separator: ", ")
                let plan = FilePlan(source: input.url, destination: destination, tags: preset.extract && tagChanges ? tagsBeforePurge : nil, purge: purge, expectedSize: stamp.0, expectedDate: stamp.1)
                detail += FilenameMask.fields.filter { $0 != "Skip" && tags.value($0) != input.tags.value($0) }.map { "\($0): \(input.tags.value($0).isEmpty ? "(empty)" : input.tags.value($0)) → \(tags.value($0).isEmpty ? "(empty)" : tags.value($0))" }
                previews.append(.init(statusText: statusText, source: input.url, plan: plan, detail: detail.joined(separator: "\n"), issue: nil))
            } catch { previews.append(.init(source: input.url, plan: nil, detail: "", issue: error.localizedDescription)) }
        }
        try cancellation.check(); progress(inputs.count, inputs.count)
        return previews
    }
}

struct DuplicateReport {
    var matches: [URL: String]
    var unreadable: Int
    var scanned: Int
}
extension LibraryTools {
    static func duplicates(_ root: URL, inputs: [URL], cancellation: JobCancellation, progress: (Int, String) -> Void) throws -> DuplicateReport {
        try SymbolicLinks.validate(root)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { throw TagError(message: "The library folder is unavailable.") }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles,.skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return true }) else { throw TagError(message: "Cannot read library.") }
        var index: [String: [URL]] = [:], count = 0, unreadable = 0
        for case let url as URL in enumerator {
            try cancellation.check()
            if SymbolicLinks.isLink(url) { continue }
            guard url.pathExtension.lowercased() == "mp3", (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            count += 1
            do { let hash = try FileJobs.hash(url, audioOnly: true, cancellation: cancellation); index[hash, default: []].append(url) }
            catch { try cancellation.check(); unreadable += 1 }
            if count % 10 == 0 { progress(count, url.lastPathComponent) }
        }
        if let error = enumerationError { throw TagError(message: "Library scan incomplete: " + error.localizedDescription) }
        var matches: [URL: String] = [:]
        if inputs.isEmpty {
            for urls in index.values where urls.count > 1 {
                for url in urls { matches[url] = urls.filter { $0 != url }.map(\.path).joined(separator: "\n") }
            }
        } else {
            var incoming: [URL: String] = [:]
            for url in inputs {
                try cancellation.check()
                do {
                    let hash = try FileJobs.hash(url, audioOnly: true, cancellation: cancellation)
                    incoming[url] = hash
                    if !(index[hash] ?? []).contains(where: { $0.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path }) {
                        index[hash, default: []].append(url)
                    }
                } catch { try cancellation.check(); unreadable += 1 }
            }
            for (url, hash) in incoming {
                let urls = (index[hash] ?? []).filter { $0.resolvingSymlinksInPath().path != url.resolvingSymlinksInPath().path }
                if !urls.isEmpty { matches[url] = urls.map(\.path).joined(separator: "\n") }
            }
        }
        try cancellation.check(); progress(count, "Complete")
        return .init(matches: matches, unreadable: unreadable, scanned: count)
    }
}

extension FileJobs {
    static func caseOnlySameFile(source: URL, destination: URL) -> Bool {
        guard source.path != destination.path, source.path.compare(destination.path, options: .caseInsensitive) == .orderedSame,
              let a = try? FileManager.default.attributesOfItem(atPath: source.path),
              let b = try? FileManager.default.attributesOfItem(atPath: destination.path) else { return false }
        return a[.systemFileNumber] as? NSNumber == b[.systemFileNumber] as? NSNumber && a[.systemNumber] as? NSNumber == b[.systemNumber] as? NSNumber
    }
    static func destinationConflict(source: URL, destination: URL) -> Bool {
        FileManager.default.fileExists(atPath: destination.path) && !caseOnlySameFile(source: source, destination: destination)
    }
    static func rename(source: URL, destination: URL) throws {
        try SymbolicLinks.validate(source)
        try SymbolicLinks.validate(destination)
        if caseOnlySameFile(source: source, destination: destination) {
            let temporary = source.deletingLastPathComponent().appendingPathComponent(".TagCraft-Rename-" + UUID().uuidString)
            try FileManager.default.moveItem(at: source, to: temporary)
            do { try FileManager.default.moveItem(at: temporary, to: destination) }
            catch { try? FileManager.default.moveItem(at: temporary, to: source); throw error }
        } else { try FileManager.default.moveItem(at: source, to: destination) }
    }
}

struct CharacterDiff {
    static func segments(before: String, after: String, proposed: Bool) -> [(String, Bool)] {
        let left = Array(before), right = Array(after)
        let columns = right.count + 1
        var lengths = Array(repeating: 0, count: (left.count + 1) * columns)
        if !left.isEmpty && !right.isEmpty {
            for i in stride(from: left.count - 1, through: 0, by: -1) {
                for j in stride(from: right.count - 1, through: 0, by: -1) {
                    lengths[i * columns + j] = left[i] == right[j] ? 1 + lengths[(i+1)*columns+j+1] : max(lengths[(i+1)*columns+j], lengths[i*columns+j+1])
                }
            }
        }
        var unchangedLeft = Set<Int>(), unchangedRight = Set<Int>()
        var i = 0, j = 0
        while i < left.count && j < right.count {
            if left[i] == right[j] { unchangedLeft.insert(i); unchangedRight.insert(j); i += 1; j += 1 }
            else if lengths[(i+1)*columns+j] >= lengths[i*columns+j+1] { i += 1 }
            else { j += 1 }
        }
        let values = proposed ? right : left, unchanged = proposed ? unchangedRight : unchangedLeft
        var segments: [(String, Bool)] = []
        for (index, character) in values.enumerated() {
            let changed = !unchanged.contains(index)
            if let last = segments.last, last.1 == changed { segments[segments.count-1].0.append(character) }
            else { segments.append((String(character), changed)) }
        }
        return segments
    }
}

struct WorkspaceSession: Codable, Equatable {
    var workspace: String?
    var library: String?
    var recentWorkspaces: [String]
}

struct ArtworkSummary {
    var kind: String
    var data: Data?
    var count: Int
    static func read(_ urls: [URL]) -> ArtworkSummary {
        guard !urls.isEmpty else { return .init(kind: "No files selected", count: 0) }
        var first: Data?, initialized = false, mixed = false, errors = 0
        for url in urls {
            do {
                let image = try ID3(Data(contentsOf: url, options: .mappedIfSafe)).artworkData
                if !initialized { first = image; initialized = true }
                else if image != first { mixed = true }
                if mixed { break }
            } catch { errors += 1 }
        }
        if errors > 0 { return .init(kind: "Artwork could not be read for some files", count: urls.count) }
        if mixed { return .init(kind: "Mixed artwork (or some files have none)", count: urls.count) }
        return .init(kind: first == nil ? "No embedded artwork" : urls.count == 1 ? "Current artwork" : "Same artwork in all checked files", data: first, count: urls.count)
    }
}
