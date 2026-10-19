import Foundation

struct MusicContext {
    var artist: String?
    var album: String?
    var disc: String?
    var notes: [String] = []
    static func isVersion(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(live|remix|mix|acoustic|instrumental|radio edit|extended|remaster(?:ed)?|demo|version)\b"#, options: .regularExpression) != nil
    }
    static func usefulFolder(_ name: String) -> Bool {
        !["music", "downloads", "documents", "desktop", "unknown", "new folder", "various", "mp3", "singles", "temp", "test", "organized"].contains(name.lowercased()) && name.range(of: #"^\d{1,4}$"#, options: .regularExpression) == nil && !name.isEmpty
    }
    static func read(_ url: URL, inputs: [PreparationInput], knownArtists: [String]) -> MusicContext {
        var result = MusicContext()
        var folder = url.deletingLastPathComponent()
        if let match = folder.lastPathComponent.range(of: #"(?i)^(?:cd|disc|disk)[ _-]*(\d{1,2})$"#, options: .regularExpression) {
            result.disc = String(folder.lastPathComponent[match]).filter(\.isNumber)
            folder.deleteLastPathComponent()
        }
        let siblings = inputs.filter { $0.url.deletingLastPathComponent() == url.deletingLastPathComponent() }
        let album = folder.lastPathComponent, artist = folder.deletingLastPathComponent().lastPathComponent
        let taggedArtists = Set(siblings.map(\.tags.artist).filter { !$0.isEmpty })
        let taggedAlbums = Set(siblings.map(\.tags.album).filter { !$0.isEmpty })
        if let name = knownArtists.first(where: { MagicAnalyzer.key($0) == MagicAnalyzer.key(artist) }), usefulFolder(artist) {
            result.artist = name
            result.notes.append("Parent artist folder agrees with a known artist.")
        } else if taggedArtists.count == 1 { result.artist = taggedArtists.first }
        let albumSupported = taggedAlbums.contains(where: { MagicAnalyzer.key($0) == MagicAnalyzer.key(album) })
        let parentArtistKnown = knownArtists.contains { MagicAnalyzer.key($0) == MagicAnalyzer.key(artist) }
        if usefulFolder(album), albumSupported || parentArtistKnown && siblings.count >= 2 {
            result.album = taggedAlbums.first(where: { MagicAnalyzer.key($0) == MagicAnalyzer.key(album) }) ?? album
        }
        let numbers = siblings.compactMap { input -> Int? in
            let stem = input.url.deletingPathExtension().lastPathComponent
            guard let range = stem.range(of: #"^\d{1,3}(?=[ ._-])"#, options: .regularExpression) else { return nil }
            return Int(stem[range])
        }.sorted()
        if numbers.count >= 2, Set(numbers).count == numbers.count, numbers.last! - numbers.first! == numbers.count - 1 {
            result.notes.append("Selected neighboring files form a consecutive track sequence (\(numbers.first!)–\(numbers.last!)).")
        }
        return result
    }
}

struct QualityFinding: Codable, Identifiable {
    var id: String { path + "\u{1f}" + field + "\u{1f}" + reason }
    var path: String
    var field: String
    var reason: String
    var suggestion: String?
    var original: String? = nil
}
struct TagQuality {
    static let artistVariationReason = "Artist naming variations"
    static func preferredArtist(_ counts: [String: Int], rules: CleanRules) -> String? {
        let lines: [String] = rules.exceptions.components(separatedBy: "\n")
        let trimmed: [String] = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let exceptions: [String] = trimmed.filter { !$0.isEmpty }.sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            return left < right
        }
        func corrected(_ name: String) -> String {
            if let exact = exceptions.first(where: { LibraryTools.normalized($0) == LibraryTools.normalized(name) }) { return exact }
            var result = name
            for exception in exceptions {
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: exception) + "(?![\\p{L}\\p{N}])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: exception))
            }
            return result
        }
        var preferredCounts: [String: Int] = [:]
        for (name, count) in counts { preferredCounts[corrected(name), default: 0] += count }
        return preferredCounts.keys.sorted { preferredCounts[$0]! == preferredCounts[$1]! ? $0 < $1 : preferredCounts[$0]! > preferredCounts[$1]! }.first
    }

    static func findings(path: String, tags: Tags, artwork: Bool) -> [QualityFinding] {
        var values: [QualityFinding] = []
        func add(_ field: String, _ reason: String, _ suggestion: String? = nil) { values.append(.init(path: path, field: field, reason: reason, suggestion: suggestion, original: tags.value(field))) }
        for field in ["Artist", "Title", "Album", "Album Artist", "Genre", "Year", "Track"] where tags.value(field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add(field, "Missing " + field.lowercased()) }
        for field in FilenameMask.fields where field != "Skip" {
            let value = tags.value(field), trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value != trimmed { add(field, "Leading or trailing whitespace", trimmed) }
        }
        if !tags.year.isEmpty {
            let year = Int(tags.year.prefix(4)) ?? 0
            if tags.year.range(of: #"^\d{4}(?:-\d{2}(?:-\d{2})?)?$"#, options: .regularExpression) == nil || year < 1000 || year > Calendar.current.component(.year, from: Date()) + 1 { add("Year", "Suspicious year or date; verify the release") }
        }
        for field in ["Track", "Disc"] {
            let value = tags.value(field)
            guard !value.isEmpty else { continue }
            let numbers = value.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
            if !(1...2).contains(numbers.count) || numbers.contains(where: { ($0 ?? 0) < 1 }) || (numbers.count == 2 && (numbers[0] ?? 0) > (numbers[1] ?? 0)) { add(field, "Invalid number or number/total") }
        }
        if !artwork { add("Artwork", "Missing embedded artwork") }
        return values
    }
    static func consistency(_ records: [LibraryRecord], rules: CleanRules = CleanRules()) -> [QualityFinding] {
        var findings: [QualityFinding] = []
        let variants = Dictionary(grouping: records.filter { !$0.tags.artist.isEmpty }, by: { LibraryTools.normalized($0.tags.artist) })
        for group in variants.values where Set(group.map(\.tags.artist)).count > 1 {
            let counts = Dictionary(grouping: group, by: { $0.tags.artist })
            let canonical = preferredArtist(counts.mapValues { $0.count }, rules: rules)!
            for item in group where item.tags.artist != canonical { findings.append(.init(path: item.path, field: "Artist", reason: artistVariationReason, suggestion: canonical, original: item.tags.artist)) }
        }
        let albums = Dictionary(grouping: records.filter { !$0.tags.album.isEmpty }, by: { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path + "\u{1f}" + $0.tags.album.lowercased() })
        for group in albums.values where Set(group.map(\.tags.albumArtist)).count > 1 {
            let nonempty = Set(group.map(\.tags.albumArtist).filter { !$0.isEmpty })
            for item in group { findings.append(.init(path: item.path, field: "Album Artist", reason: "Inconsistent album artist within this album folder", suggestion: item.tags.albumArtist.isEmpty && nonempty.count == 1 ? nonempty.first : nil, original: item.tags.albumArtist)) }
        }
        return findings
    }
}
struct CSVReport {
    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    static func inventory(_ snapshot: LibrarySnapshot) -> [[String]] {
        [["Library", "Snapshot", "Path", "Artist", "Title", "Album", "Album Artist", "Genre", "Year", "Track", "Disc", "Bytes", "Artwork", "Bitrate kbps", "Read error"]] + (snapshot.records ?? []).map { item in
            [snapshot.root, snapshot.updated.ISO8601Format(), item.path, item.tags.artist, item.tags.title, item.tags.album, item.tags.albumArtist, item.tags.genre, item.tags.year, item.tags.track, item.tags.extra["TPOS"] ?? "", String(item.bytes), item.hasArtwork ? "Yes" : "No", item.bitrate.map(String.init) ?? "", item.error ?? ""]
        }
    }
    static func quality(_ findings: [QualityFinding], root: String = "", updated: Date? = nil) -> [[String]] { [["Location", "Report Date", "Path", "Field", "Issue", "Suggestion"]] + findings.map { [root, updated?.ISO8601Format() ?? "", $0.path, $0.field, $0.reason, $0.suggestion ?? ""] } }
}

struct MixedTagValues {
    static func value(_ field: String, in tags: [Tags]) -> (value: String, mixed: Bool) {
        let values = Set(tags.map { $0.value(field) })
        return values.count > 1 ? ("", true) : (values.first ?? "", false)
    }
}
