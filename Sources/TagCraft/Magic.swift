import Foundation

struct MagicCandidate: Identifiable {
    var id: String { artist + "\u{1f}" + title + "\u{1f}" + track }
    var artist: String
    var title: String
    var track = ""
    var score: Int
    var evidence: [String]
}
struct MagicSuggestion: Identifiable {
    var id: URL { source }
    var source: URL
    var original: Tags
    var proposed: Tags
    var cleaned: String
    var alternatives: [MagicCandidate]
    var reasons: [String]
    var warnings: [String]
    var highConfidence: Bool
    var included: Bool
    var problem: String?
    var size: Int?
    var modified: Date?
    var hasChanges: Bool { proposed != original || destination?.path != source.path }
    var destination: URL? { try? FilenameTemplate("{Artist} - {Title}").filename(tags: proposed).mapFilename(in: source.deletingLastPathComponent()) }
}
private extension String {
    func mapFilename(in folder: URL) -> URL { folder.appendingPathComponent(self) }
}
struct MagicLexicon {
    static let abbreviations = ["DJ", "EP", "LP", "BPM", "USA", "UK", "NYC", "VIP", "EDM", "TV", "feat.", "ft.", "vs.", "Vol.", "Pt."]
    static let words: Set<String> = {
        if let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) {
            return Set(text.split(whereSeparator: { $0.isNewline }).map { $0.lowercased() })
        }
        return Set("a an and are as at be by can do for from go he her here i in is it live love me mix my night no not of on one or our remix she so song the their them there they this time to track us was we what when where who why with you your".split(separator: " ").map(String.init))
    }()
    static func spelling(_ value: String, original: String) -> (String, [String]) {
        var result = value, notes: [String] = []
        for token in original.components(separatedBy: CharacterSet.letters.inverted).filter({ !$0.isEmpty }) {
            // Unknown words aren't automatically acronyms. Only preserve casing already present.
            guard (2...5).contains(token.count), token == token.uppercased(), !words.contains(token.lowercased()) else { continue }
            let expression = try! NSRegularExpression(pattern: "(?i)(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}])")
            let range = NSRange(result.startIndex..., in: result)
            if expression.firstMatch(in: result, range: range) != nil {
                result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: token)
                notes.append("Preserved existing acronym spelling \(token); not inferred just because a word is absent from the dictionary.")
            }
        }
        return (result, notes)
    }
}
struct MagicAnalyzer {
    static func key(_ text: String) -> String { LibraryTools.normalized(text) }
    static func analyze(_ inputs: [PreparationInput], rules: CleanRules, libraryArtists: [String], cancellation: JobCancellation, progress: (Int, Int) -> Void) throws -> [MagicSuggestion] {
        let exceptions = rules.exceptions.split(separator: "\n").map(String.init)
        let knownNames = exceptions + libraryArtists + inputs.map(\.tags.artist).filter { !$0.isEmpty }
        var canonical: [String: String] = [:]
        // Personal exceptions win over all other spelling sources.
        for name in knownNames where canonical[key(name)] == nil { canonical[key(name)] = name }
        var batchFrequency: [String: Int] = [:]
        for input in inputs {
            let raw = URL(fileURLWithPath: input.url.lastPathComponent).deletingPathExtension().lastPathComponent
            for part in raw.components(separatedBy: " - ") where !part.isEmpty { batchFrequency[key(part), default: 0] += 1 }
        }
        var suggestions: [MagicSuggestion] = []
        for (index, input) in inputs.enumerated() {
            try cancellation.check(); progress(index, inputs.count)
            let stamp = FileJobs.fingerprint(input.url)
            do {
                if let issue = input.issue { throw TagError(message: issue) }
                let data = try Data(contentsOf: input.url, options: .mappedIfSafe)
                let original = try ID3(data).tags
                var raw = input.url.deletingPathExtension().lastPathComponent
                var reasons: [String] = [], warnings: [String] = []
                while raw.lowercased().hasSuffix(".mp3") { raw = String(raw.dropLast(4)); reasons.append("Removed a repeated .mp3 extension.") }
                // Promote only narrowly identified trailing download/presentation labels.
                let labels = ["Official Music Video", "Official Video", "Official Audio", "Lyric Video", "Lyrics", "1080p", "720p", "2160p", "4K", "HD", "HQ", "320kbps", "128kbps"]
                for _ in 0..<6 {
                    let before = raw
                    for label in labels {
                        let pattern = "(?i)\\s*(?:[-–—_]\\s*(?:[\\(\\[\\{]\\s*)?|[\\(\\[\\{]\\s*)" + NSRegularExpression.escapedPattern(for: label).replacingOccurrences(of: " ", with: "[ _]+") + "\\s*[\\)\\]\\}]?\\s*$"
                        let changed = raw.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                        if changed != raw { reasons.append("Suggested removal of trailing \(label) presentation/quality label."); raw = changed }
                    }
                    if raw == before { break }
                }
                let web = "(?i)\\s*(?:[-–—_]\\s*|[\\(\\[\\{]\\s*)(?:https?[:_]+|www\\.)[^ ]+?[\\)\\]\\}]?\\s*$"
                let webClean = raw.replacingOccurrences(of: web, with: "", options: .regularExpression)
                if webClean != raw { raw = webClean; reasons.append("Suggested removal of a trailing web address."); warnings.append("Review removal of web-address-like text.") }
                let video = try! NSRegularExpression(pattern: "\\s*[-–—]\\s*([A-Za-z0-9_-]{11})\\s*$")
                if let match = video.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                    let token = (raw as NSString).substring(with: match.range(at: 1))
                    if token.contains(where: \.isNumber) && token.contains(where: \.isUppercase) {
                        raw = (raw as NSString).substring(to: match.range.location)
                        reasons.append("Suggested removal of a video-ID-like suffix."); warnings.append("A video ID cannot be confirmed locally; review this removal.")
                    }
                }
                var preparation = rules
                preparation.removeTrackPrefix = false
                preparation.exceptions += "\n" + MagicLexicon.abbreviations.joined(separator: "\n")
                let prepared = try preparation.clean(raw + ".mp3", tags: Tags())
                let spelling = MagicLexicon.spelling(String(prepared.0.dropLast(4)), original: raw)
                var cleaned = spelling.0
                reasons += spelling.1
                if prepared.1.contains(where: { $0.contains("unspaced hyphen") }) { warnings.append("A hyphen was inferred as a delimiter; review the field boundary.") }
                var trackNumber = ""
                let numbered = try! NSRegularExpression(pattern: "^([0-9]{1,3})\\s+-\\s+")
                if let match = numbered.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
                    trackNumber = (cleaned as NSString).substring(with: match.range(at: 1))
                    cleaned = (cleaned as NSString).substring(from: NSMaxRange(match.range))
                    reasons.append("Recognized leading track number \(trackNumber).")
                }
                var groupStack: [Character] = []
                var brokenGroups = false
                for char in cleaned {
                    if char == "(" { groupStack.append(")") }
                    else if char == "[" { groupStack.append("]") }
                    else if char == "{" { groupStack.append("}") }
                    else if ")] }".contains(char) && char != " " {
                        if groupStack.last == char { groupStack.removeLast() } else { brokenGroups = true }
                    }
                }
                if brokenGroups || !groupStack.isEmpty { warnings.append("Unmatched parentheses or brackets require review.") }
                var candidates: [MagicCandidate] = []
                func candidate(_ artist: String, _ title: String, _ layout: String, base: Int) {
                    var artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !artist.isEmpty, !title.isEmpty else { return }
                    var score = base, evidence = [layout]
                    if let name = canonical[key(artist)] {
                        artist = name
                        let abbreviationOnly = MagicLexicon.abbreviations.contains(where: { key($0) == key(name) }) && !libraryArtists.contains(name) && !inputs.contains(where: { key($0.tags.artist) == key(name) })
                        if !abbreviationOnly { score += 40 }
                        evidence.append(exceptions.contains(name) ? "Artist matches a personal spelling exception." : libraryArtists.contains(name) ? "Artist matches an existing library folder." : "Artist agrees with a tagged artist in this batch.")
                    }
                    if !original.artist.isEmpty && key(artist) == key(original.artist) { score += 26; evidence.append("Artist agrees with this file's tag.") }
                    if !original.title.isEmpty && key(title) == key(original.title) { score += 26; evidence.append("Title agrees with this file's tag.") }
                    if (batchFrequency[key(artist)] ?? 0) >= 2 { score += 8; evidence.append("Artist-like text repeats across the selected batch.") }
                    let item = MagicCandidate(artist: artist, title: title, track: trackNumber, score: score, evidence: evidence)
                    if let i = candidates.firstIndex(where: { $0.id == item.id }) { if candidates[i].score < item.score { candidates[i] = item } }
                    else { candidates.append(item) }
                }
                // Consider every separator outside balanced groups, including reversed layouts.
                let chars = Array(cleaned); var depth = 0
                if chars.count >= 3 {
                    for offset in 0...(chars.count - 3) {
                        if "([{ ".contains(chars[offset]) && chars[offset] != " " { depth += 1 }
                        if ")] }".contains(chars[offset]) && chars[offset] != " " { depth = max(0, depth-1) }
                        if depth == 0 && String(chars[offset..<offset+3]) == " - " {
                            let left = String(chars[..<offset]), right = String(chars[(offset+3)...])
                            candidate(left, right, "Filename interpreted as Artist - Title.", base: 24)
                            candidate(right, left, "Filename interpreted as Title - Artist.", base: 20)
                        }
                    }
                }
                let context = MusicContext.read(input.url, inputs: inputs, knownArtists: knownNames)
                if candidates.isEmpty, let artist = context.artist { candidate(artist, cleaned, "Artist suggested by album-folder context.", base: 26) }
                // A final version suffix belongs to the title, not a second artist boundary.
                if let boundary = cleaned.range(of: " - ") {
                    let artist = String(cleaned[..<boundary.lowerBound])
                    let remainder = String(cleaned[boundary.upperBound...])
                    if let version = remainder.range(of: " - ", options: .backwards) {
                        let suffix = String(remainder[version.upperBound...])
                        if MusicContext.isVersion(suffix), suffix.rangeOfCharacter(from: CharacterSet(charactersIn: "()[]{}")) == nil {
                            candidate(artist, String(remainder[..<version.lowerBound]) + " (" + suffix + ")", "Recognized recording version; preserve its identity.", base: 27)
                            warnings.append("Review placement of the recording-version label.")
                        }
                    }
                    if let feature = artist.range(of: #"(?i)\s+(?:feat\.?|ft\.?)\s+"#, options: .regularExpression) {
                        candidate(String(artist[..<feature.lowerBound]), remainder + " (feat. " + String(artist[feature.upperBound...]) + ")", "Alternative: featured credit in title instead of artist.", base: 20)
                        warnings.append("Featured artist credit preserved; choose your preferred placement.")
                    }
                }
                if candidates.isEmpty && !original.artist.isEmpty { candidate(original.artist, cleaned, "Title-only filename combined with existing artist tag.", base: 30) }
                if !original.artist.isEmpty && !original.title.isEmpty {
                    candidate(original.artist, original.title, "Existing artist/title tags retained as an alternative.", base: 15)
                }
                candidates.sort { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
                guard let best = candidates.first else { throw TagError(message: "No reliable artist/title boundary found. Enter artist and title, or use the individual actions.") }
                var proposed = original; proposed.artist = best.artist; proposed.title = best.title
                if !trackNumber.isEmpty {
                    proposed.track = trackNumber
                    if !original.track.isEmpty && original.track != trackNumber { warnings.append("Filename track number disagrees with the saved tag.") }
                }
                if proposed.album.isEmpty, let album = context.album { proposed.album = album; warnings.append("Review album inferred from folder: " + album) }
                if proposed.extra["TPOS", default: ""].isEmpty, let disc = context.disc { proposed.extra["TPOS"] = disc; reasons.append("Disc number inferred from CD/Disc folder.") }
                reasons += context.notes
                let conflicts = (!original.artist.isEmpty && key(best.artist) != key(original.artist)) || (!original.title.isEmpty && key(best.title) != key(original.title))
                if conflicts { warnings.append("Proposed artist/title disagrees with existing tags.") }
                if best.evidence.contains("Existing artist/title tags retained as an alternative.") && key(cleaned) != key(best.artist + " " + best.title) { warnings.append("Existing tags may not describe this filename; verify the recording.") }
                let margin = best.score - (candidates.dropFirst().first?.score ?? 0)
                let high = best.score >= 60 && margin >= 15 && warnings.isEmpty
                if margin < 15 { warnings.append("More than one interpretation has similar evidence.") }
                if best.score < 60 { warnings.append("Insufficient supporting evidence; manual review required.") }
                let destination = try FilenameTemplate("{Artist} - {Title}").filename(tags: proposed).mapFilename(in: input.url.deletingLastPathComponent())
                let problem = destination.path != input.url.path && FileJobs.destinationConflict(source: input.url, destination: destination) ? "Destination already exists." : nil
                reasons += best.evidence
                suggestions.append(.init(source: input.url, original: original, proposed: proposed, cleaned: prepared.0, alternatives: Array(candidates.prefix(6)), reasons: reasons, warnings: warnings, highConfidence: high, included: high && problem == nil, problem: problem, size: stamp.0, modified: stamp.1))
            } catch {
                suggestions.append(.init(source: input.url, original: input.tags, proposed: input.tags, cleaned: input.url.lastPathComponent, alternatives: [], reasons: [], warnings: [], highConfidence: false, included: false, problem: error.localizedDescription, size: stamp.0, modified: stamp.1))
            }
        }
        for i in suggestions.indices where !suggestions[i].hasChanges { suggestions[i].included = false }
        let grouped = Dictionary(grouping: suggestions.filter { $0.destination != nil }, by: { $0.destination!.path.lowercased() })
        for i in suggestions.indices where (grouped[suggestions[i].destination?.path.lowercased() ?? ""]?.count ?? 0) > 1 {
            suggestions[i].problem = "Multiple selected files would have the same destination."; suggestions[i].included = false
        }
        try cancellation.check(); progress(inputs.count, inputs.count)
        return suggestions
    }
}
