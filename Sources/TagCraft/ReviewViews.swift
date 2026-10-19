import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor extension Model {
    func refreshBatchValues() {
        let checked = batchCandidates.filter { batchTargets.contains($0.url) }
        for field in FilenameMask.fields where field != "Skip" && !batchFields.contains(field) {
            let summary = MixedTagValues.value(field, in: checked.map(\.tags))
            if summary.mixed { batchMixed.insert(field) } else { batchMixed.remove(field) }
            batchDraft.set(field, summary.value)
        }
    }
    func exportCSV(_ rows: [[String]], name: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = name + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try CSVReport.encode(rows).write(to: url, atomically: true, encoding: .utf8) }
        catch { message = "CSV export failed: " + error.localizedDescription }
    }
    func exportDuplicateReport() {
        exportCSV([["Source", "Matching audio locations"]] + duplicateResults.keys.sorted { $0.path < $1.path }.map { [$0.path, duplicateResults[$0] ?? ""] }, name: "TagCraft Duplicates")
    }
    func checkTagQuality() {
        guard !busy else { return }
        let inputs = selected.isEmpty ? tracks : selected
        let rules = cleanRules
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressDone = 0; progressTotal = inputs.count; progressText = "Checking tag quality"
        runningTask = Task {
            do {
                let findings = try await Task.detached {
                    var records: [LibraryRecord] = []
                    for (index, track) in inputs.enumerated() {
                        try cancel.check()
                        do {
                            let parsed = try ID3(Data(contentsOf: track.url, options: .mappedIfSafe))
                            records.append(.init(path: track.url.path, bytes: 0, tags: parsed.tags, hasArtwork: parsed.artworkData != nil))
                        } catch { records.append(.init(path: track.url.path, bytes: 0, tags: Tags(), hasArtwork: false, error: error.localizedDescription)) }
                        Task { @MainActor in self.progressDone = index + 1 }
                    }
                    try cancel.check()
                    return records.flatMap { record -> [QualityFinding] in
                        if let error = record.error { return [.init(path: record.path, field: "Read Error", reason: error)] }
                        return TagQuality.findings(path: record.path, tags: record.tags, artwork: record.hasArtwork)
                    } + TagQuality.consistency(records.filter { $0.error == nil }, rules: rules)
                }.value
                qualityFindings = findings; qualityRoot = folder?.path ?? "Workspace"; qualityDate = Date(); qualityMessage = ""
                qualityReason = ""; qualityAvailableReasons = Array(Set(findings.map(\.reason))).sorted(); qualityScopeSnapshot = nil; qualityLoading = false; showQuality = true
            } catch { message = cancel.isCancelled ? "Tag quality check cancelled." : error.localizedDescription }
            busy = false
        }
    }
    func applyQuality(_ changes: [(QualityFinding, String)]) {
        do {
            var plans: [FilePlan] = []
            for (path, rows) in Dictionary(grouping: changes, by: { $0.0.path }) {
                let url = URL(fileURLWithPath: path), stamp = FileJobs.fingerprint(URL(fileURLWithPath: path))
                let current = try ID3(Data(contentsOf: url, options: .mappedIfSafe)).tags
                var tags = current
                var fields = Set<String>()
                for (finding, value) in rows {
                    if let original = finding.original, current.value(finding.field) != original { throw TagError(message: "Tags changed since this report. Run a new quality check before applying: " + path) }
                    guard fields.insert(finding.field).inserted else { throw TagError(message: "Choose only one correction per field and file.") }
                    tags.set(finding.field, value)
                }
                if tags != current { plans.append(.init(source: url, destination: url, tags: tags, expectedSize: stamp.0, expectedDate: stamp.1)) }
            }
            showQuality = false
            if plans.isEmpty { message = "No tag changes needed." } else { runPlans(plans, label: "Tag Quality Corrections") }
        } catch { qualityMessage = error.localizedDescription }
    }
}
struct QualityReviewView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Set<String>()
    @State private var edits: [String: String] = [:]
    @State private var query = ""
    var filtered: [QualityFinding] { m.qualityFindings.filter { (m.qualityReason.isEmpty || $0.reason == m.qualityReason) && (query.isEmpty || ($0.path + " " + $0.field + " " + $0.reason).localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tag Quality — Review Corrections").font(.title2.bold())
            Text(m.qualityRoot).font(.caption).textSelection(.enabled)
            Text("Nothing is changed automatically. Enter or review a replacement, then check the fields to apply. Blank checked values remove a tag. Artwork and audio issues are informational. Library reports reflect the last manual snapshot.").foregroundStyle(.secondary)
            Picker("Issue type", selection: $m.qualityReason) {
                Text("All issue types").tag("")
                ForEach(m.qualityAvailableReasons, id: \.self) { Text($0).tag($0) }
            }
            Text("Only checked issues in the current view are applied. Changing filters clears checks; typed replacements are kept.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Filter files or issues", text: $query).textFieldStyle(.roundedBorder)
                Button("Export CSV…") { m.exportCSV(CSVReport.quality(filtered, root: m.qualityRoot, updated: m.qualityDate), name: "TagCraft Tag Quality") }.disabled(m.qualityLoading)
            }
            if m.qualityLoading { HStack { ProgressView().controlSize(.small); Text("Loading selected issue type…").font(.caption) } }
            if filtered.isEmpty && !m.qualityLoading { ContentUnavailableView("No matching issues", systemImage: "checkmark.seal") }
            List(filtered) { finding in
                VStack(alignment: .leading, spacing: 5) {
                    Text(URL(fileURLWithPath: finding.path).lastPathComponent).bold()
                    Text(finding.reason).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        Text("Current value:").foregroundStyle(.secondary)
                        Text(finding.original.map { $0.isEmpty ? "Empty" : String(reflecting: $0) } ?? "Unavailable in this report")
                            .textSelection(.enabled)
                    }.font(.callout)
                    if FilenameMask.fields.contains(finding.field) && finding.field != "Skip" {
                        HStack {
                            Toggle(finding.field, isOn: Binding(get: { chosen.contains(finding.id) }, set: { if $0 { chosen.insert(finding.id) } else { chosen.remove(finding.id) } })).frame(width: 140, alignment: .leading)
                            TextField(finding.suggestion == nil ? "Enter replacement" : "Suggested replacement", text: Binding(get: { edits[finding.id] ?? finding.suggestion ?? "" }, set: { edits[finding.id] = $0 })).textFieldStyle(.roundedBorder)
                        }
                    }
                    Text(finding.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(.vertical, 5)
            }
            .disabled(m.qualityLoading)
            if !m.qualityMessage.isEmpty { Text(m.qualityMessage).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Text("\(filtered.count) issues in \(Set(filtered.map(\.path)).count) files · \(filtered.filter { chosen.contains($0.id) }.count) corrections checked").font(.caption)
                Spacer(); Button("Done") { dismiss() }
                Button("Apply Checked Corrections") {
                    m.applyQuality(filtered.filter { chosen.contains($0.id) }.map { ($0, edits[$0.id] ?? $0.suggestion ?? "") })
                }.buttonStyle(.borderedProminent).disabled(!filtered.contains { chosen.contains($0.id) } || m.busy || m.qualityLoading)
            }
        }.padding(24).frame(width: 880, height: 700)
            .onChange(of: m.qualityReason) { _, _ in chosen.removeAll(); m.reloadQualityScope() }
            .onChange(of: query) { _, _ in chosen.removeAll() }
            .onDisappear { m.qualityReloadToken = UUID() }
    }
}
