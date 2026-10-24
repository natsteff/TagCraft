import SwiftUI

struct BroomIcon: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 10, y: 1)); path.addLine(to: CGPoint(x: 10, y: 11))
            path.move(to: CGPoint(x: 6, y: 11)); path.addLine(to: CGPoint(x: 14, y: 11))
            path.addLine(to: CGPoint(x: 18, y: 20)); path.addLine(to: CGPoint(x: 2, y: 20)); path.closeSubpath()
            for x in [6.0,10.0,14.0] { path.move(to: CGPoint(x: 10 + (x-10)*0.45, y: 13)); path.addLine(to: CGPoint(x: x, y: 19)) }
        }.stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 21).rotationEffect(.degrees(-30))
    }
}
struct MagicReviewView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Magic — Review Suggestions").font(.title2.bold())
            Text(m.selectionSummary).font(.callout)
            Text("Local analysis combines Clean rules, filename layouts, existing tags, library artists, folder context and batch patterns. Nothing changes until Apply. Confidence is an evidence label, not a probability.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Label("Strong evidence: changed files included by default", systemImage: "checkmark.circle").foregroundStyle(.green)
                Label("Needs review: initially excluded", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
                Button("Exclude All") { for i in m.magicSuggestions.indices { m.magicSuggestions[i].included = false } }
            }.font(.caption)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach($m.magicSuggestions) { $row in
                        MagicSuggestionRow(row: $row)
                    }
                }
            }
            if !m.message.isEmpty { Text(m.message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack {
                Text("\(m.magicSuggestions.filter { $0.included && $0.hasChanges }.count) of \(m.magicSuggestions.count) files included · \(m.magicSuggestions.filter { !$0.hasChanges }.count) unchanged").font(.caption)
                Spacer(); Button("Cancel") { dismiss() }
                Button("Apply Reviewed Changes") { m.applyMagic() }.buttonStyle(.borderedProminent)
                    .disabled(!m.magicSuggestions.contains(where: { $0.included && $0.hasChanges }))
            }
        }.padding(24).frame(minWidth: 950, idealWidth: 950, maxWidth: .infinity, minHeight: 480, idealHeight: 690, maxHeight: .infinity).background(ResizableReviewSheet())
    }
}
struct MagicSuggestionRow: View {
    @Binding var row: MagicSuggestion
    @State private var choice = ""
    @State private var confirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Include", isOn: $row.included).disabled(!row.hasChanges)
                Text(row.source.lastPathComponent).font(.headline).textSelection(.enabled)
                Spacer()
                Text(!row.hasChanges ? "No change needed" : confirmation ? "Manually reviewed" : row.highConfidence ? "Strong evidence" : "Needs review")
                    .font(.caption.bold()).foregroundStyle(!row.hasChanges ? Color.secondary : row.highConfidence ? Color.green : Color.orange)
            }
            Text("Prepared filename: " + row.cleaned).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if !row.alternatives.isEmpty {
                Picker("Interpretation", selection: $choice) {
                    Text("Suggested / edited values").tag("")
                    ForEach(row.alternatives) { item in Text(item.artist + " — " + item.title).tag(item.id) }
                }.onChange(of: choice) { _, value in
                    guard let candidate = row.alternatives.first(where: { $0.id == value }) else { return }
                    row.proposed.artist = candidate.artist; row.proposed.title = candidate.title
                    if !candidate.track.isEmpty { row.proposed.track = candidate.track }
                    row.reasons = candidate.evidence
                    row.included = false; confirmation = false
                }
            }
            HStack {
                Text("Artist").frame(width: 38, alignment: .leading)
                TextField("Artist", text: $row.proposed.artist)
                Text("Title").frame(width: 28)
                TextField("Title", text: $row.proposed.title)
                Text("Track #")
                TextField("", text: $row.proposed.track).accessibilityLabel("Track number").frame(width: 50)
            }.textFieldStyle(.roundedBorder)
                .onChange(of: row.proposed) { _, _ in row.included = false; confirmation = false }
            HStack {
                Text("Album")
                TextField("Album", text: $row.proposed.album)
                Text("Disc #")
                TextField("", text: Binding(get: { row.proposed.extra["TPOS"] ?? "" }, set: { row.proposed.extra["TPOS"] = $0.isEmpty ? nil : $0 })).frame(width: 60)
            }.textFieldStyle(.roundedBorder)
                .onChange(of: row.proposed) { _, _ in row.included = false; confirmation = false }
            VStack(alignment: .leading, spacing: 2) {
                if !row.hasChanges { Text("No change needed").foregroundStyle(.secondary) }
                if row.original.album != row.proposed.album { Text("Album: \(row.original.album.isEmpty ? "(empty)" : row.original.album) → \(row.proposed.album)") }
                if row.original.extra["TPOS"] != row.proposed.extra["TPOS"] { Text("Disc: \(row.original.extra["TPOS"] ?? "(empty)") → \(row.proposed.extra["TPOS"] ?? "(empty)")") }
                if row.original.artist != row.proposed.artist { Text("Artist: \(row.original.artist.isEmpty ? "(empty)" : row.original.artist) → \(row.proposed.artist)") }
                if row.original.title != row.proposed.title { Text("Title: \(row.original.title.isEmpty ? "(empty)" : row.original.title) → \(row.proposed.title)") }
                if row.original.track != row.proposed.track { Text("Track: \(row.original.track.isEmpty ? "(empty)" : row.original.track) → \(row.proposed.track)") }
                if let destination = row.destination {
                    FilenameDiffText(before: row.source.lastPathComponent, after: destination.lastPathComponent, proposed: true)
                } else { Text("Artist and title are required.").foregroundStyle(.orange) }
            }.font(.caption).textSelection(.enabled)
            ForEach(Array(row.reasons.enumerated()), id: \.offset) { _, reason in Text("• " + reason).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(row.warnings.enumerated()), id: \.offset) { _, warning in Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if let problem = row.problem { Text("Initial analysis: " + problem).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Reviewed, include this file") { confirmation = true; row.included = true }.disabled(row.included || !row.hasChanges || row.destination == nil)
                Button("Use Artist for Similar Files") { applyArtistToBatch() }
                    .disabled(row.proposed.artist.trimmingCharacters(in: .whitespaces).isEmpty)
            }.font(.caption)
        }.padding(14).background(row.highConfidence ? Color.secondary.opacity(0.06) : Color.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
    @EnvironmentObject private var m: Model
    private func applyArtistToBatch() {
        let old = row.alternatives.first?.artist ?? row.original.artist
        let corrected = row.proposed.artist
        guard !MagicAnalyzer.key(old).isEmpty else { return }
        for index in m.magicSuggestions.indices where MagicAnalyzer.key(m.magicSuggestions[index].alternatives.first?.artist ?? m.magicSuggestions[index].original.artist) == MagicAnalyzer.key(old) {
            m.magicSuggestions[index].proposed.artist = corrected
            m.magicSuggestions[index].included = false
        }
    }
}
