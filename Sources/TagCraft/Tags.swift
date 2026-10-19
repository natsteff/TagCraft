import Foundation

struct TagError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
struct Tags: Equatable, Codable {
    static let extraFields: [(id: String, label: String)] = [
        ("TPOS", "Disc"), ("TCOM", "Composer"), ("TPE3", "Conductor"),
        ("TBPM", "BPM"), ("TPUB", "Publisher"), ("TCOP", "Copyright"),
        ("TENC", "Encoded By"), ("TLAN", "Language"), ("TIT1", "Grouping"),
        ("TIT3", "Subtitle"), ("TSRC", "ISRC"), ("TEXT", "Lyricist")
    ]
    var extra: [String: String] = [:]
    var title = "", artist = "", album = "", albumArtist = "", year = "", genre = "", track = ""
}
struct ID3 {
    struct Frame { var id: String; var payload: Data; var flags: Data }
    var version = 3
    var frames: [Frame] = []
    var audioOffset = 0
    var tags = Tags()
    static let keys = ["TIT2", "TPE1", "TALB", "TPE2", "TYER", "TDRC", "TCON", "TRCK"] + Tags.extraFields.map(\.id)
    static func sync(_ bytes: Data) -> Int { bytes.reduce(0) { ($0 << 7) | Int($1 & 127) } }
    static func number(_ n: Int, sync: Bool) -> Data {
        let shift = sync ? 7 : 8
        let mask = sync ? 127 : 255
        return Data((0..<4).reversed().map { UInt8((n >> ($0 * shift)) & mask) })
    }
    init(_ data: Data) throws {
        guard data.count >= 3, data.prefix(3) == Data("ID3".utf8) else { return }
        guard data.count >= 10 else { throw TagError(message: "Truncated ID3 header.") }
        version = Int(data[3])
        guard [3,4].contains(version), data[5] == 0 else {
            throw TagError(message: "This file uses an unsupported ID3 version or extended flags. It has been left unchanged.")
        }
        audioOffset = 10 + Self.sync(data.subdata(in: 6..<10))
        guard audioOffset <= data.count else { throw TagError(message: "Truncated ID3 tag.") }
        var pos = 10
        while pos + 10 <= audioOffset && data[pos] != 0 {
            let idData = data.subdata(in: pos..<pos+4)
            guard idData.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }), let id = String(data: idData, encoding: .ascii) else { throw TagError(message: "Invalid ID3 frame.") }
            let sizeBytes = data.subdata(in: pos+4..<pos+8)
            let size = version == 4 ? Self.sync(sizeBytes) : sizeBytes.reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, pos + 10 + size <= audioOffset else { throw TagError(message: "Invalid ID3 frame size.") }
            let flags = data.subdata(in: pos+8..<pos+10)
            let payload = data.subdata(in: pos+10..<pos+10+size)
            if Self.keys.contains(id), flags != Data([0,0]) { throw TagError(message: "Encoded or protected text frames cannot be edited safely.") }
            frames.append(Frame(id: id, payload: payload, flags: flags))
            pos += 10 + size
        }
        func value(_ ids: [String]) -> String {
            guard let f = frames.first(where: { ids.contains($0.id) }), let encoding = f.payload.first else { return "" }
            let bytes = f.payload.dropFirst()
            let text: String?
            switch encoding {
            case 0: text = String(data: bytes, encoding: .isoLatin1)
            case 1: text = String(data: bytes, encoding: .utf16)
            case 2: text = String(data: bytes, encoding: .utf16BigEndian)
            case 3: text = String(data: bytes, encoding: .utf8)
            default: text = nil
            }
            return (text ?? "").trimmingCharacters(in: .controlCharacters)
        }
        tags = Tags(title: value(["TIT2"]), artist: value(["TPE1"]), album: value(["TALB"]), albumArtist: value(["TPE2"]), year: value(["TDRC","TYER"]), genre: value(["TCON"]), track: value(["TRCK"]))
        for field in Tags.extraFields {
            let text = value([field.id])
            if !text.isEmpty { tags.extra[field.id] = text }
        }
    }
    func writing(_ tags: Tags, original: Data) -> Data {
        var body = Data()
        func append(_ f: Frame) {
            body.append(Data(f.id.utf8)); body.append(Self.number(f.payload.count, sync: version == 4)); body.append(f.flags); body.append(f.payload)
        }
        for f in frames where !Self.keys.contains(f.id) { append(f) }
        let values = [("TIT2",tags.title),("TPE1",tags.artist),("TALB",tags.album),("TPE2",tags.albumArtist),(version == 4 ? "TDRC" : "TYER",tags.year),("TCON",tags.genre),("TRCK",tags.track)] + Tags.extraFields.map { ($0.id, tags.extra[$0.id] ?? "") }
        for (key, value) in values where !value.isEmpty {
            var payload: Data
            if let latin = value.data(using: .isoLatin1) {
                payload = Data([0]); payload.append(latin)
            } else {
                payload = Data([1]); payload.append(value.data(using: .utf16)!)
            }
            append(Frame(id: key, payload: payload, flags: Data([0,0])))
        }
        body.append(Data(repeating: 0, count: 1024))
        var result = Data("ID3".utf8); result.append(contentsOf: [UInt8(version),0,0]); result.append(Self.number(body.count, sync: true)); result.append(body); result.append(original.dropFirst(audioOffset))
        return result
    }
}

enum LibraryPlacement: String, Codable, CaseIterable, Identifiable {
    case settings = "Use library settings"
    case albums = "Use album folders"
    case individual = "Individual tracks"
    case direct = "Directly under artist"
    var id: String { rawValue }
    var label: String { self == .albums ? "Organize into album folders under artist" : rawValue }
}
struct LibraryStructure: Codable, Equatable {
    var useLetterFolders = true
    var defaultPlacement = LibraryPlacement.direct
    var useIndividualFolder = false
    var individualFolderName = "Individual Tracks"
    var summary: String {
        (useLetterFolders ? "Library / Letter / Artist" : "Library / Artist") + " · " + (defaultPlacement == .albums ? "Albums in folders under artist" : "Album tracks directly under artist") + " · Individual tracks " + (useIndividualFolder ? "in " + individualFolderName : "directly under artist") + "."
    }
}
struct SymbolicLinks {
    static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }
    static func validate(_ url: URL) throws {
        var part = url.standardizedFileURL
        while part.path != "/" {
            if isLink(part) {
                // Standard macOS filesystem aliases are not user library redirects.
                let aliases = ["/var": "/private/var", "/tmp": "/private/tmp", "/etc": "/private/etc"]
                let target = try? FileManager.default.destinationOfSymbolicLink(atPath: part.path)
                let absoluteTarget = target.map { $0.hasPrefix("/") ? $0 : "/" + $0 }
                if aliases[part.path] == nil || aliases[part.path] != absoluteTarget {
                    throw TagError(message: "Symbolic links are skipped: " + part.path)
                }
            }
            part.deleteLastPathComponent()
        }
    }
}
struct LibraryPath {
    static func clean(_ name: String) -> String {
        let result = name.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return result == "." || result == ".." ? "_" : result
    }
    static func destination(root: URL, artist: String, filename: String, album: String = "", structure: LibraryStructure = LibraryStructure(), placement: LibraryPlacement = .settings) throws -> URL {
        let artist = clean(artist)
        guard !artist.isEmpty else { throw TagError(message: "An artist tag is required before moving to the library.") }
        let letter = artist.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased().first!
        let bucket = letter.isASCII && letter.isNumber ? "0-9" : (letter.isASCII && letter.isLetter ? String(letter) : "#")
        var folder = structure.useLetterFolders ? root.appendingPathComponent(bucket, isDirectory: true) : root
        folder.appendPathComponent(artist, isDirectory: true)
        let albumName = clean(album)
        let choice: LibraryPlacement = placement == .settings
            ? (albumName.isEmpty ? .individual : (structure.defaultPlacement == .albums ? .albums : .direct))
            : placement
        if choice == .albums && !albumName.isEmpty {
            folder.appendPathComponent(albumName, isDirectory: true)
        } else if (choice == .individual || choice == .albums) && structure.useIndividualFolder {
            let name = structure.individualFolderName
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  name != ".", name != "..", clean(name) == name else {
                throw TagError(message: "Enter a valid custom individual tracks folder name without path separators or control characters.")
            }
            folder.appendPathComponent(name, isDirectory: true)
        }
        let destination = folder.appendingPathComponent(filename)
        try SymbolicLinks.validate(destination)
        return destination
    }
}

struct FilenameCleaner {
    static func parts(_ filename: String) throws -> (artist: String, title: String) {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let delimiter = stem.range(of: " - ") else {
            throw TagError(message: "Expected Artist - Song Title.mp3. Add the delimiter or supply artist and title tags before cleaning.")
        }
        let artist = String(stem[..<delimiter.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(stem[delimiter.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty, !title.isEmpty else { throw TagError(message: "Artist and song title must both be present.") }
        return (artist, title)
    }
    static func clean(_ filename: String, tags: Tags = Tags()) throws -> String {
        func tidy(_ value: String) -> String {
            value.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                .capitalized(with: Locale(identifier: "en_US_POSIX"))
        }
        let components: (artist: String, title: String)
        if let parsed = try? parts(filename) { components = parsed }
        else if !tags.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !tags.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components = (tags.artist, tags.title)
        } else { throw TagError(message: "Cannot determine artist and title. Use Artist - Song Title.mp3 or fill both tags first.") }
        let artist = LibraryPath.clean(tidy(components.artist))
        let title = LibraryPath.clean(tidy(components.title))
        guard !artist.isEmpty, !title.isEmpty else { throw TagError(message: "Artist or title is empty after cleaning.") }
        return artist + " - " + title + ".mp3"
    }
}

struct FilenameMask {
    static let fields = ["Artist", "Title", "Track", "Album", "Album Artist", "Year", "Genre"] + Tags.extraFields.map(\.label) + ["Skip"]
    static let presets = ["Artist - Title", "Title - Artist", "Track # - Artist - Title", "Custom Mask"]
    static let masks = ["{Artist} - {Title}", "{Title} - {Artist}", "{Track} - {Artist} - {Title}"]
    let regex: NSRegularExpression
    let captures: [String]
    let literals: [String]
    let ignoredGroups: Set<String>
    init(_ mask: String, ignoredGroups: Set<String> = []) throws {
        let tokens = try NSRegularExpression(pattern: "\\{([^{}]+)\\}")
        let source = mask as NSString
        let matches = tokens.matches(in: mask, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { throw TagError(message: "Insert at least one tag variable.") }
        var names: [String] = []; var separators: [String] = []; var pattern = "^"; var position = 0
        for (index, match) in matches.enumerated() {
            let name = source.substring(with: match.range(at: 1))
            guard Self.fields.contains(name) else { throw TagError(message: "Unknown variable: \(name)") }
            guard name == "Skip" || !names.contains(name) else { throw TagError(message: "Each tag variable may appear only once.") }
            let literal = source.substring(with: NSRange(location: position, length: match.range.location - position))
            guard index == 0 || !literal.isEmpty else { throw TagError(message: "Add a separator between variables.") }
            guard !literal.contains("{") && !literal.contains("}") else { throw TagError(message: "Unmatched braces in mask.") }
            separators.append(literal)
            pattern += NSRegularExpression.escapedPattern(for: literal) + (index == matches.count - 1 ? "(.+)" : "(.+?)")
            names.append(name); position = NSMaxRange(match.range)
        }
        let tail = source.substring(from: position)
        guard !tail.contains("{") && !tail.contains("}") else { throw TagError(message: "Unmatched braces in mask.") }
        guard names.contains(where: { $0 != "Skip" }) else { throw TagError(message: "Include at least one tag field besides Skip.") }
        pattern += NSRegularExpression.escapedPattern(for: tail) + "$"
        regex = try NSRegularExpression(pattern: pattern)
        captures = names
        literals = separators + [tail]
        self.ignoredGroups = ignoredGroups
    }
    private func depths(_ text: String) -> [Int] {
        let units = Array(text.utf16)
        var result = Array(repeating: 0, count: units.count + 1)
        for (name, open, close) in [("()", UInt16(40), UInt16(41)), ("{}", 123, 125), ("[]", 91, 93)] where ignoredGroups.contains(name) {
            var stack: [Int] = []
            for (index, unit) in units.enumerated() {
                if unit == open { stack.append(index) }
                if unit == close, let start = stack.popLast() {
                    for position in (start + 1)...index { result[position] += 1 }
                }
            }
        }
        return result
    }
    private func values(_ filename: String) -> [String]? {
        let text = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let source = text as NSString
        if ignoredGroups.isEmpty {
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
            return captures.indices.map { source.substring(with: match.range(at: $0 + 1)) }
        }
        let depth = depths(text)
        func literalEnd(_ literal: String, _ start: Int) -> Int? {
            let length = (literal as NSString).length
            guard start >= 0, start + length <= source.length,
                  source.substring(with: NSRange(location: start, length: length)) == literal else { return nil }
            return start + length
        }
        var attempts = 0
        func split(_ field: Int, _ start: Int) -> [String]? {
            attempts += 1
            guard attempts < 10000, start < source.length else { return nil }
            let separator = literals[field + 1]
            if field == captures.count - 1 {
                let end = source.length - (separator as NSString).length
                guard end > start, literalEnd(separator, end) == source.length else { return nil }
                return [source.substring(with: NSRange(location: start, length: end - start))]
            }
            // Brackets explicitly written in the mask remain literal boundaries.
            let structural = separator.rangeOfCharacter(from: CharacterSet(charactersIn: "(){}[]")) != nil
            for end in (start + 1)...source.length {
                if !structural && depth[end] > depth[start] { continue }
                guard let next = literalEnd(separator, end), let rest = split(field + 1, next) else { continue }
                return [source.substring(with: NSRange(location: start, length: end - start))] + rest
            }
            return nil
        }
        guard let start = literalEnd(literals[0], 0) else { return nil }
        return split(0, start)
    }
    func extract(_ filename: String, existing: Tags) throws -> Tags {
        guard let values = values(filename) else {
            throw TagError(message: "Filename does not match the selected layout and delimiter settings.")
        }
        var tags = existing
        for (index, name) in captures.enumerated() where name != "Skip" {
            let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw TagError(message: "\(name) is empty.") }
            if name == "Track" || name == "Disc" {
                guard value.range(of: "^[0-9]+(?:/[0-9]+)?$", options: .regularExpression) != nil else { throw TagError(message: "\(name) must be a number or number/total.") }
            }
            tags.set(name, value)
        }
        return tags
    }
    func review(_ filename: String) -> (warning: String?, ignored: [String]) {
        guard let values = values(filename) else { return (nil, []) }
        var reasons: [String] = []
        let separators = literals.dropFirst().dropLast().filter { !$0.isEmpty }
        if values.contains(where: { value in
            let source = value as NSString
            let depth = depths(value)
            return separators.contains { separator in
                var offset = 0
                while offset < source.length {
                    let range = source.range(of: separator, range: NSRange(location: offset, length: source.length - offset))
                    if range.location == NSNotFound { break }
                    if depth[range.location] == 0 { return true }
                    offset = NSMaxRange(range)
                }
                return false
            }
        }) {
            reasons.append("A separator also appears inside captured text; another split may be intended.")
        }
        func unbalanced(_ value: String) -> Bool {
            var stack: [Character] = []
            for character in value {
                if character == "(" { stack.append(")") }
                else if character == "[" { stack.append("]") }
                else if character == "{" { stack.append("}") }
                else if character == ")" || character == "]" || character == "}" {
                    guard stack.last == character else { return true }
                    stack.removeLast()
                }
            }
            return !stack.isEmpty
        }
        if values.contains(where: unbalanced) {
            reasons.append("A captured section has unmatched parentheses or brackets. This may be intentional; check the mask.")
        }
        let ignored = captures.enumerated().compactMap { $0.element == "Skip" ? values[$0.offset] : nil }
        return (reasons.isEmpty ? nil : reasons.joined(separator: " "), ignored)
    }

}
extension Tags {
    func value(_ name: String) -> String {
        switch name {
        case "Artist": return artist
        case "Title": return title
        case "Track": return track
        case "Album": return album
        case "Album Artist": return albumArtist
        case "Year": return year
        case "Genre": return genre
        default: return Self.extraFields.first(where: { $0.label == name }).flatMap { extra[$0.id] } ?? ""
        }
    }
    mutating func set(_ name: String, _ value: String) {
        switch name {
        case "Artist": artist = value
        case "Title": title = value
        case "Track": track = value
        case "Album": album = value
        case "Album Artist": albumArtist = value
        case "Year": year = value
        case "Genre": genre = value
        default: if let field = Self.extraFields.first(where: { $0.label == name }) { extra[field.id] = value }
        }
    }
}

struct FilenameTemplate {
    let mask: String
    init(_ mask: String) throws {
        let tokens = try NSRegularExpression(pattern: "\\{([^{}]+)\\}")
        let source = mask as NSString
        let matches = tokens.matches(in: mask, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { throw TagError(message: "Insert at least one tag variable.") }
        for match in matches {
            let name = source.substring(with: match.range(at: 1))
            guard FilenameMask.fields.contains(name), name != "Skip" else {
                throw TagError(message: name == "Skip" ? "Skip is only for extracting tags. Remove it from the rename mask." : "Unknown variable: \(name)")
            }
        }
        let literals = tokens.stringByReplacingMatches(in: mask, range: NSRange(location: 0, length: source.length), withTemplate: "")
        guard !literals.contains("{") && !literals.contains("}") else { throw TagError(message: "Unmatched braces in mask.") }
        guard literals.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)) == nil else {
            throw TagError(message: "Use a filename mask without path separators or control characters.")
        }
        self.mask = mask
    }
    func filename(tags: Tags) throws -> String {
        let tokens = try NSRegularExpression(pattern: "\\{([^{}]+)\\}")
        let source = mask as NSString
        let matches = tokens.matches(in: mask, range: NSRange(location: 0, length: source.length))
        let result = NSMutableString(string: mask)
        for match in matches.reversed() {
            let name = source.substring(with: match.range(at: 1))
            let value = tags.value(name).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw TagError(message: "Missing \(name) tag.") }
            result.replaceCharacters(in: match.range, with: LibraryPath.clean(value))
        }
        let stem = (result as String).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, stem != ".", stem != "..", !stem.hasPrefix(".") else {
            throw TagError(message: "The mask produces an empty, invalid or hidden filename.")
        }
        let filename = stem + ".mp3"
        guard filename.utf8.count <= 255 else { throw TagError(message: "Proposed filename is too long.") }
        return filename
    }
}

struct PurgeField: Identifiable {
    let id: String
    let frames: Set<String>
    static let fields: [PurgeField] = [
        .init(id: "Title", frames: ["TIT2"]), .init(id: "Artist", frames: ["TPE1"]),
        .init(id: "Album", frames: ["TALB"]), .init(id: "Album Artist", frames: ["TPE2"]),
        .init(id: "Year / Recording Date", frames: ["TYER", "TDRC"]),
        .init(id: "Genre", frames: ["TCON"]), .init(id: "Track", frames: ["TRCK"])
    ] + Tags.extraFields.map { .init(id: $0.label, frames: [$0.id]) } + [
        .init(id: "Artwork", frames: ["APIC"]), .init(id: "Comments", frames: ["COMM"]),
        .init(id: "Lyrics (plain and synchronized)", frames: ["USLT", "SYLT"]),
        .init(id: "Ratings / Play Counts", frames: ["POPM", "PCNT"]),
        .init(id: "Custom Text Fields", frames: ["TXXX"]),
        .init(id: "Custom URL Fields", frames: ["WXXX"])
    ]
}
extension ID3 {
    func purging(_ ids: Set<String>, original: Data) -> Data {
        var body = Data()
        for frame in frames where !ids.contains(frame.id) {
            body.append(Data(frame.id.utf8))
            body.append(Self.number(frame.payload.count, sync: version == 4))
            body.append(frame.flags)
            body.append(frame.payload)
        }
        // Remove an empty v2 tag entirely; leave the remaining file bytes intact.
        if body.isEmpty { return Self.purgeLegacy(ids, data: Data(original.dropFirst(audioOffset))) }
        body.append(Data(repeating: 0, count: 1024))
        var result = Data("ID3".utf8)
        result.append(contentsOf: [UInt8(version), 0, 0])
        result.append(Self.number(body.count, sync: true))
        result.append(body)
        result.append(original.dropFirst(audioOffset))
        return Self.purgeLegacy(ids, data: result)
    }
}

extension ID3 {
    static let legacyRanges: [(String, Range<Int>)] = [("TIT2", 3..<33), ("TPE1", 33..<63), ("TALB", 63..<93), ("TYER", 93..<97), ("COMM", 97..<127)]
    static func legacyFields(_ data: Data) -> Set<String> {
        guard data.count >= 128 else { return [] }
        let tail = Data(data.suffix(128))
        guard tail.prefix(3) == Data("TAG".utf8) else { return [] }
        var fields = Set<String>()
        for (key, range) in legacyRanges {
            let actual = key == "COMM" && tail[125] == 0 ? 97..<125 : range
            if tail[actual].contains(where: { $0 != 0 && $0 != 32 }) { fields.insert(key) }
        }
        if tail[125] == 0 && tail[126] > 0 { fields.insert("TRCK") }
        if tail[127] != 255 { fields.insert("TCON") }
        return fields
    }
    static func purgeLegacy(_ ids: Set<String>, data: Data) -> Data {
        guard data.count >= 128 else { return data }
        var result = data
        let offset = data.count - 128
        guard data.subdata(in: offset..<offset+3) == Data("TAG".utf8) else { return data }
        let hasTrack = data[offset + 125] == 0
        for (key, range) in legacyRanges where ids.contains(key) || (key == "TYER" && ids.contains("TDRC")) {
            let actual = key == "COMM" && hasTrack ? 97..<125 : range
            for index in actual { result[offset + index] = 0 }
        }
        if ids.contains("TRCK") && hasTrack { result[offset + 126] = 0 }
        if ids.contains("TCON") { result[offset + 127] = 255 }
        return result
    }
}

struct SourceFiles {
    static func contains(_ url: URL, in root: URL) -> Bool {
        let parent = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let child = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return child.starts(with: parent)
    }
    static func includes(_ url: URL, root: URL, includeSubfolders: Bool = false) -> Bool {
        if includeSubfolders { return contains(url, in: root) }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path
    }
    static func mp3URLs(root: URL, includeSubfolders: Bool = false, shouldCancel: () -> Bool = { false }, skippedLink: () -> Void = {}) -> [URL] {
        guard (try? SymbolicLinks.validate(root)) != nil else { skippedLink(); return [] }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !includeSubfolders { options.insert(.skipsSubdirectoryDescendants) }
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: options) else { return [] }
        var files: [URL] = []
        for case let url as URL in entries {
            if shouldCancel() { break }
            if SymbolicLinks.isLink(url) { skippedLink(); continue }
            guard includes(url, root: root, includeSubfolders: includeSubfolders),
                  url.pathExtension.lowercased() == "mp3",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(url)
        }
        return files
    }
}
