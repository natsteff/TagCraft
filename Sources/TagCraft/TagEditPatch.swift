import Foundation

/// Blank inputs are never deletion requests. Removal requires an explicit clear.
struct TagEditPatch {
    static var fields: [String] { FilenameMask.fields.filter { $0 != "Skip" } }
    var draft: Tags
    var checked: Set<String>
    var cleared: Set<String>
    var effective: Set<String> {
        checked.filter { cleared.contains($0) || !draft.value($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    func applying(to original: Tags) -> Tags {
        var result = original
        for field in effective { result.set(field, cleared.contains(field) ? "" : draft.value(field)) }
        return result
    }
    var summary: String {
        let sets = effective.subtracting(cleared).sorted()
        let removals = effective.intersection(cleared).sorted()
        return ([sets.isEmpty ? nil : "Set: " + sets.joined(separator: ", "), removals.isEmpty ? nil : "Remove: " + removals.joined(separator: ", ")].compactMap { $0 }).joined(separator: "\n")
    }
}
