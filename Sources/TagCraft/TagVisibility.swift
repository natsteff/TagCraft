import Foundation

enum TagVisibility {
    static var tags: [String] { TagEditPatch.fields.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    static let defaultColumns: Set<String> = ["Filename", "Artist", "Title", "Album", "Track", "Year", "Status"]
    static var columnChoices: Set<String> { Set(tags).union(["Filename", "Status"]) }
    static func inspectorFields(fromPurge selected: Set<String>) -> Set<String> {
        let removed = PurgeField.fields.filter { selected.contains($0.id) }.reduce(into: Set<String>()) { $0.formUnion($1.frames) }
        let standard: [String: Set<String>] = ["Artist": ["TPE1"], "Title": ["TIT2"], "Album": ["TALB"], "Album Artist": ["TPE2"], "Year": ["TYER", "TDRC"], "Genre": ["TCON"], "Track": ["TRCK"]]
        return Set(tags.filter { field in
            let frames = standard[field] ?? Set(Tags.extraFields.filter { $0.label == field }.map(\.id))
            return frames.isDisjoint(with: removed)
        })
    }
    static func load(_ key: String, defaults: UserDefaults, fallback: Set<String>, allowed: Set<String>) -> Set<String> {
        guard let stored = defaults.stringArray(forKey: key) else { return fallback }
        return Set(stored).intersection(allowed)
    }
    static func groups(inspector: Set<String>) -> (shown: [String], hidden: [String]) {
        (tags.filter { inspector.contains($0) }, tags.filter { !inspector.contains($0) })
    }
}
