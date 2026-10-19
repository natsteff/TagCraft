import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers
import Darwin
import CoreServices

final class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void
    init(_ folder: URL, callback: @escaping () -> Void) {
        self.callback = callback
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderMonitor>.fromOpaque(info).takeUnretainedValue().callback()
        }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.6,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
    static func ancestors(_ folder: URL) -> [URL] {
        var urls = [folder]
        var current = folder
        while current.path != "/" {
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            urls.append(parent); current = parent
        }
        return urls.reversed()
    }
}
@MainActor extension Model {
    func openFolder(_ url: URL) {
        guard !busy else { return }
        if dirty {
            let alert = NSAlert(); alert.messageText = "Discard unsaved inspector edits?"
            alert.informativeText = "Opening another workspace replaces the current selection. Save Tags first if you want to keep these edits."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Discard and Open")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        folder = url
        AppPreferences.defaults.set(url.path, forKey: "lastMusicFolder")
        recentFolders = [url.path] + recentFolders.filter { $0 != url.path }
        recentFolders = Array(recentFolders.prefix(12))
        AppPreferences.defaults.set(recentFolders, forKey: "recentFolders")
        saveSession()
        configureMonitor(); scan()
    }
    func saveSession() {
        AppPreferences.defaults.synchronize()
        SettingsFiles.save(WorkspaceSession(workspace: folder?.path, library: library?.path, recentWorkspaces: recentFolders), "workspace-session.json")
    }
    func clearRecentWorkspaces() {
        recentFolders = []
        AppPreferences.defaults.set([], forKey: "recentFolders")
        saveSession()
    }
    func configureMonitor() {
        folderMonitor = nil
        guard autoRefresh, let folder else { return }
        folderMonitor = FolderMonitor(folder) { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, !self.busy, !self.dirty else { return }
                self.scan()
            }
        }
    }
    func runPlans(_ plans: [FilePlan], label: String) {
        guard !busy, !plans.isEmpty else { return }
        busy = true; showMoves = false; cancellation = JobCancellation()
        progressDone = 0; progressTotal = plans.count; progressText = label
        failures = []; lastErrors = []
        let cancel = cancellation
        let storedUndoTracks = undoTracks
        let originalTracks = Dictionary(uniqueKeysWithValues: tracks.map { ($0.url, $0) })
        runningTask = Task {
            let results = await Task.detached {
                FileJobs.run(plans, cancellation: cancel) { done, total, name in
                    Task { @MainActor in self.progressDone = done; self.progressTotal = total; self.progressText = label + ": " + name }
                }
            }.value
            undoMoves = []; undoTracks = [:]
            for result in results {
                if let error = result.error {
                    lastErrors.append(result.source.lastPathComponent + ": " + error)
                    if let plan = plans.first(where: { $0.source == result.source }) { failures.append(plan) }
                    continue
                }
                playback.update(source: result.source, destination: result.destination, tags: result.tags)
                var track = originalTracks[result.source] ?? storedUndoTracks[result.destination] ?? Track(url: result.source, tags: result.tags ?? Tags())
                if result.destination.path != result.source.path {
                    undoMoves.append((result.destination, result.source)); undoTracks[result.source] = track
                }
                track.url = result.destination
                if let tags = result.tags { track.tags = tags }
                tracks.removeAll { $0.url == result.source }
                if let folder, SourceFiles.includes(result.destination, root: folder, includeSubfolders: includeSubfolders) { tracks.append(track) }
            }
            busy = false; selection = []; loadSelection()
            let success = results.filter { $0.error == nil }.count
            message = "\(label): \(success) completed, \(failures.count) failed" + (cancel.isCancelled ? ", cancelled with \(plans.count - results.count) not started." : ".")
            if !lastErrors.isEmpty { message += "\n" + lastErrors.joined(separator: "\n") }
        }
    }
    func prepareMovePreview() {
        guard !busy else { return }
        guard let library else { pick(library: true); return }
        movePlacement = .settings; artistChoices = [:]; duplicateResults = [:]
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressText = "Reading existing library artist folders"; progressTotal = 0
        let useLetterFolders = libraryStructure.useLetterFolders
        runningTask = Task {
            let incoming = selected
            let matches = await Task.detached { () -> ([String], [URL: [String]]) in
                let names = LibraryTools.artistNames(library, useLetterFolders: useLetterFolders, cancellation: cancel)
                let options = Dictionary(uniqueKeysWithValues: incoming.map { ($0.url, LibraryTools.suggestions($0.tags.artist, names: names)) })
                return (names, options)
            }.value
            if cancel.isCancelled { busy = false; message = "Artist matching cancelled; no files changed."; return }
            artistNames = matches.0; artistSuggestions = matches.1
            busy = false; previewMove()
        }
    }
    func updateStatistics() {
        guard !busy, let library, let store = statisticsStore, statisticsReady else { return }
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        let includeAudio = includeAudioStatistics, reuse = reuseStatistics, rules = cleanRules
        progressDone = 0; progressTotal = 0; progressText = "Updating library statistics…"
        runningTask = Task {
            do {
                let snapshot = try await Task.detached {
                    let snapshot = try await LibraryScanner.scan(library, previous: nil, reuse: reuse, includeAudio: includeAudio, store: store, rules: rules, cancellation: cancel) { progress in
                        Task { @MainActor in
                            self.progressDone = progress.done; self.progressTotal = progress.total
                            self.progressText = progress.text
                        }
                    }
                    return snapshot
                }.value
                stats = snapshot
                message = "Library statistics updated for \(ScanProgress.count(snapshot.tracks)) tracks." + ((snapshot.skippedSymbolicLinks ?? 0) > 0 ? " \(ScanProgress.count(snapshot.skippedSymbolicLinks ?? 0)) symbolic links skipped." : "")
            } catch { message = cancel.isCancelled ? "Statistics update cancelled. Completed reads checkpointed for reuse; previous complete snapshot retained." : error.localizedDescription }
            busy = false
        }
    }
    func checkDuplicates() {
        guard !busy, let library else { return }
        let inputs = selected
        let reviewingMove = showMoves && (operation == "Move to Library" || operation == "Preparation Workflow")
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressDone = 0; progressTotal = 0; progressText = "Comparing library audio payloads…"
        runningTask = Task {
            do {
                let result = try await Task.detached {
                    try LibraryTools.duplicates(library, inputs: inputs.map(\.url), cancellation: cancel) { count, name in
                        Task { @MainActor in self.progressDone = count; self.progressText = "Hashed \(count) files · " + name }
                    }
                }.value
                let report = result.matches
                duplicateResults = report
                if reviewingMove {
                    moves = moves.map { row in
                        var item = row
                        if let match = report[row.source] {
                            item.warning = "Matching compressed audio already in library:\n" + match
                            excluded.insert(row.source)
                        }
                        return item
                    }
                    message = "Duplicate check complete. Matching files are excluded by default; review before including. \(result.unreadable) files could not be hashed."
                    busy = false
                    return
                }
                operation = "Duplicate Check"
                moves = report.keys.sorted { $0.path < $1.path }.map { .init(source: $0, destination: nil, issue: "Same compressed audio payload as:\n" + report[$0]!) }
                duplicateSummary = "\(result.scanned) library files scanned; \(result.unreadable) unreadable files skipped."
                showMoves = true
                message = (report.isEmpty ? "No identical compressed-audio payloads found." : "Found \(report.count) files with matching audio payloads. No files were changed.") + " \(result.scanned) library files scanned; \(result.unreadable) unreadable files skipped."
            } catch { message = cancel.isCancelled ? "Duplicate check cancelled; no files changed." : error.localizedDescription }
            busy = false
        }
    }
    func beginMagic() {
        guard !busy, !selected.isEmpty else { return }
        let inputs = selected.map { PreparationInput(url: $0.url, tags: $0.tags, issue: $0.issue) }
        let rules = cleanRules, root = library, useLetterFolders = libraryStructure.useLetterFolders
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressDone = 0; progressTotal = inputs.count; progressText = "Magic: analyzing filenames, tags and artist spellings"
        runningTask = Task {
            do {
                let suggestions = try await Task.detached {
                    let artists = root.map { LibraryTools.artistNames($0, useLetterFolders: useLetterFolders, cancellation: cancel) } ?? []
                    return try MagicAnalyzer.analyze(inputs, rules: rules, libraryArtists: artists, cancellation: cancel) { done, total in
                        Task { @MainActor in self.progressDone = done; self.progressTotal = total }
                    }
                }.value
                magicSuggestions = suggestions; busy = false; showMagicReview = true
            } catch { busy = false; message = cancel.isCancelled ? "Magic cancelled; no files changed." : error.localizedDescription }
        }
    }
    func applyMagic() {
        let rows = magicSuggestions.filter { $0.included && $0.hasChanges }
        var paths = Set<String>(), plans: [FilePlan] = []
        do {
            for row in rows {
                guard let destination = row.destination else { throw TagError(message: "Artist and title are required for every included file.") }
                guard paths.insert(destination.path.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .current)).inserted else { throw TagError(message: "Included files have duplicate destinations. Correct or exclude them.") }
                if destination.path != row.source.path && FileJobs.destinationConflict(source: row.source, destination: destination) { throw TagError(message: "Destination already exists: " + destination.path) }
                plans.append(.init(source: row.source, destination: destination, tags: row.proposed == row.original ? nil : row.proposed, expectedSize: row.size, expectedDate: row.modified))
            }
            showMagicReview = false
            runPlans(plans, label: "Magic")
        } catch { message = error.localizedDescription }
    }
    func previewWorkflow() {
        guard !busy, !selected.isEmpty else { return }
        let inputs = selected.map { PreparationInput(url: $0.url, tags: $0.tags, issue: $0.issue) }
        let preset = workflow, root = library, structure = libraryStructure
        showWorkflow = false; busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressText = "Planning workflow"; progressDone = 0; progressTotal = inputs.count
        runningTask = Task {
            do {
                let previews = try await Task.detached {
                    try WorkflowPlanner.preview(inputs, preset: preset, library: root, structure: structure, cancellation: cancel) { done, total in
                        Task { @MainActor in self.progressDone = done; self.progressTotal = total }
                    }
                }.value
                operation = "Preparation Workflow"; planned = [:]; excluded = []
                moves = previews.map { preview in
                    if let plan = preview.plan { planned[preview.source] = plan }
                    return .init(statusText: preview.statusText, source: preview.source, destination: preview.plan?.destination, issue: preview.issue, warning: preview.detail.contains("unspaced hyphen") ? "Review inferred separators before applying extracted tags." : nil, detail: preview.detail)
                }
                busy = false
                try? await Task.sleep(for: .milliseconds(200)); showMoves = true
            } catch { busy = false; message = cancel.isCancelled ? "Workflow preview cancelled; no files changed." : error.localizedDescription }
        }
    }
    func loadTechnical() {
        guard !busy, let track = selected.first else { return }
        busy = true; progressText = "Reading audio details"; progressTotal = 0
        runningTask = Task {
            do {
                let data = try await Task.detached { try Data(contentsOf: track.url, options: .mappedIfSafe) }.value
                let id3 = try ID3(data)
                pictures = EmbeddedPicture.read(id3)
                artwork = id3.artworkData.flatMap(NSImage.init(data:))
                let asset = AVURLAsset(url: track.url)
                let duration = try await asset.load(.duration).seconds
                let audio = try await asset.loadTracks(withMediaType: .audio).first
                let rate = try await audio?.load(.estimatedDataRate) ?? 0
                let formats = try await audio?.load(.formatDescriptions) ?? []
                let sampleRate = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 0
                technical = "\(track.filename)\n\(track.url.path)\n\nSize: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))\nDuration: \(duration.isFinite ? String(format: "%.1f seconds", duration) : "Unknown")\nBitrate: \(Int(rate / 1000)) kbps\nSample rate: \(Int(sampleRate)) Hz\nID3: \(id3.audioOffset > 0 ? "v2.\(id3.version)" : "No v2 tag")"
                showTechnical = true
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    func changeArtwork(remove: Bool = false) {
        guard !busy, let track = selected.first else { return }
        var bytes: Data?
        if !remove {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg]; panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 20_000_000, NSImage(data: data) != nil else { throw TagError(message: "Choose a valid JPEG or PNG smaller than 20 MB.") }
                bytes = try ArtworkImage.prepare(data, maxEdge: artworkMaxEdge)
            } catch { message = error.localizedDescription; return }
        }
        let stamp = FileJobs.fingerprint(track.url)
        showTechnical = false
        runPlans([.init(source: track.url, destination: track.url, artwork: bytes, removeArtwork: remove, replaceAllArtwork: replaceAllArtwork, expectedSize: stamp.0, expectedDate: stamp.1)], label: "Update Artwork")
    }
}

struct CleanSettingsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clean Rules").font(.title2.bold())
            Text("Rules are saved automatically. Clean prepares raw filenames in their existing field order and never reads or changes tags. Magic combines Clean, extraction and rename in a reviewed plan.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Normalize whitespace", isOn: $m.cleanRules.whitespace)
                    Toggle("Replace underscores with spaces", isOn: $m.cleanRules.underscores)
                    Toggle("Clean separator dots", isOn: $m.cleanRules.dots)
                    Toggle("Intelligent capitalization", isOn: $m.cleanRules.capitalization)
                    Toggle("Normalize delimiters to ‘ - ’", isOn: Binding(get: { m.cleanRules.normalizeSeparators ?? true }, set: { m.cleanRules.normalizeSeparators = $0 }))
                    Toggle("Remove track-number prefixes", isOn: $m.cleanRules.removeTrackPrefix)
                    Toggle("Remove configured trailing labels", isOn: $m.cleanRules.removeSuffixes)
                    Text("Initials and decimal numbers are protected. Filename-forbidden characters still become underscores. Add artist names or acronyms below to preserve their spelling.").font(.caption).foregroundStyle(.secondary)
                }.frame(width: 300)
                VStack(alignment: .leading) {
                    Text("Spelling exceptions — one per line").font(.headline)
                    TextEditor(text: $m.cleanRules.exceptions).font(.body.monospaced()).frame(height: 120).border(.quaternary)
                    Text("Removable trailing labels — one per line").font(.headline)
                    TextEditor(text: $m.cleanRules.suffixes).font(.body.monospaced()).frame(height: 100).border(.quaternary)
                    Text("Labels are removed only at the end, after a dash or inside brackets. Live, Remix and Acoustic are not in the default removal list.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Examples from selected files").font(.headline)
            List(m.selected.prefix(5)) { track in
                VStack(alignment: .leading) {
                    Text(track.filename).font(.caption)
                    Text((try? m.cleanRules.clean(track.filename, tags: track.tags).0) ?? "Cannot clean this filename").font(.caption.bold())
                }
            }
            HStack { Button("Restore Defaults") { m.cleanRules = CleanRules() }; Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 790, height: 650)
    }
}
struct WorkflowView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preparation Workflows").font(.title2.bold())
            Text("Choose steps in execution order, save a preset, then review every file before applying. No step runs from this editor.").foregroundStyle(.secondary)
            HStack {
                TextField("Workflow name", text: $m.workflow.name).textFieldStyle(.roundedBorder)
                Menu("Load Preset") { ForEach(m.workflows) { preset in Button(preset.name) { m.workflow = preset } } }
                Button("Save Preset") {
                    if let index = m.workflows.firstIndex(where: { $0.id == m.workflow.id }) { m.workflows[index] = m.workflow }
                    else { m.workflows.append(m.workflow) }
                    SettingsFiles.save(m.workflows, "workflows.json")
                }.disabled(m.workflow.name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("New") { m.workflow = WorkflowPreset() }
            }
            Form {
                Toggle("1. Clean filename", isOn: $m.workflow.clean)
                Button("Copy Current Clean Rules") { m.workflow.cleanRules = m.cleanRules }
                Toggle("2. Extract tags from resulting filename", isOn: $m.workflow.extract)
                TextField("Extraction mask", text: $m.workflow.extractionMask)
                Button("Copy Current Extraction Layout & Delimiter Settings") {
                    m.workflow.extractionMask = m.extractionMask; m.workflow.ignoredGroups = m.ignoredGroups
                }
                Toggle("3. Purge selected tag fields", isOn: $m.workflow.purge)
                HStack {
                    Text("\(m.workflow.purgeIDs.count) frame types in preset").font(.caption)
                    Button("Copy Current Purge Selection") { m.workflow.purgeIDs = m.purgeFrameIDs }
                }
                Toggle("4. Rename from resulting tags", isOn: $m.workflow.rename)
                TextField("Rename mask", text: $m.workflow.renameMask)
                Toggle("5. Move into library", isOn: $m.workflow.move)
            }.textFieldStyle(.roundedBorder)
            Text("Example mask: {Artist} - {Title}. Purging a field used later in rename/move can make that file ineligible. Saved presets include rule and mask settings; preview shows resulting tag changes and paths.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if m.workflows.contains(where: { $0.id == m.workflow.id }) {
                    Button("Delete Preset") { m.workflows.removeAll { $0.id == m.workflow.id }; SettingsFiles.save(m.workflows, "workflows.json") }
                }
                Spacer(); Button("Close") { dismiss() }
                Button("Preview \(m.selected.count) Files") { m.previewWorkflow() }.buttonStyle(.borderedProminent).disabled(m.selected.isEmpty || m.busy || m.dirty || !(m.workflow.clean || m.workflow.extract || m.workflow.purge || m.workflow.rename || m.workflow.move))
            }
        }.padding(24).frame(width: 760, height: 560)
    }
}
struct StatisticsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var category = "Artist"
    @State private var sortOrder = [KeyPathComparator(\LibraryGroup.tracks, order: .reverse)]
    @State private var query = ""
    @State private var selectedHealth: String?
    var snapshot: LibrarySnapshot? { m.stats?.root == m.library?.path ? m.stats : nil }
    var groups: [LibraryGroup] {
        guard let snapshot else { return [] }
        let values = category == "Artist" ? snapshot.artists : category == "Genre" ? snapshot.genres : category == "Year" ? snapshot.years : category == "Bitrate" ? snapshot.bitrates ?? [] : category == "Health" ? snapshot.health ?? [] : snapshot.sampleRates ?? []
        return values.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted(using: sortOrder)
    }
    func storage(_ bytes: Int64) -> String {
        let value = Double(bytes)
        return value >= 1e12 ? String(format: "%.2f TB", value / 1e12) : String(format: "%.2f GB", value / 1e9)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Library Statistics").font(.title2.bold())
                    Text(m.library?.path ?? "Choose a library first.").font(.caption).textSelection(.enabled)
                }
                Spacer(minLength: 18)
                StatisticsBrandLogo()
            }
            HStack {
                Button("Update Library Statistics") { m.updateStatistics() }.buttonStyle(.borderedProminent).disabled(m.busy || m.library == nil || !m.statisticsReady || m.statisticsLoading)

                if let snapshot {
                    Menu("Export CSV") {
                        Button("Totals…") { m.exportCSV([["Library", "Snapshot", "Tracks", "Artists", "Albums", "Bytes", "GB", "TB", "Unreadable Tags"], [snapshot.root, snapshot.updated.ISO8601Format(), String(snapshot.tracks), String(snapshot.artistCount), String(snapshot.albumCount ?? 0), String(snapshot.bytes), String(Double(snapshot.bytes) / 1e9), String(Double(snapshot.bytes) / 1e12), String(snapshot.unreadable)]], name: "TagCraft Library Totals") }
                        Button("Current View…") { m.exportCSV([["Library", "Snapshot", "Category", "Name", "Tracks", "Bytes"]] + groups.map { [snapshot.root, snapshot.updated.ISO8601Format(), category, $0.name, String($0.tracks), String($0.bytes)] }, name: "TagCraft " + category) }
                        Button("Full Inventory…") { m.exportStatisticsInventory(snapshot) }.disabled(snapshot.records == nil && snapshot.databaseBacked != true)
                        Button("Health Report…") { m.exportStatisticsHealth(snapshot) }.disabled(snapshot.findings == nil && snapshot.databaseBacked != true)
                    }.disabled(m.busy)
                }
                Spacer()
            }
            if m.statisticsLoading { Text("Loading local statistics / migrating existing cache…").font(.caption).foregroundStyle(.secondary) }
            if !m.statisticsReady && !m.statisticsLoading {
                Text("SQLite is unavailable. Existing JSON is view-only; updates are disabled. " + m.statisticsError).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                Button("Retry Statistics Storage") { m.statisticsRestoreStarted = false; m.restoreStatistics() }
            }
            if m.busy {
                HStack {
                    if m.progressTotal > 0 { ProgressView(value: Double(m.progressDone), total: Double(m.progressTotal)).frame(width: 100) }
                    else { ProgressView().controlSize(.small) }
                    Text(m.progressText).font(.caption).lineLimit(2)
                    Spacer(); Button("Cancel") { m.cancellation.cancel() }
                }
            }
            Toggle("Reuse unchanged file records during manual updates", isOn: $m.reuseStatistics).disabled(m.busy)
            Toggle("Include duration, bitrate and sample-rate statistics (slower)", isOn: $m.includeAudioStatistics).disabled(m.busy)
            Text("Updated only on request. Reads are checkpointed in SQLite; interrupted scans can reuse them next time. The previous complete report stays visible until an update finishes. Counts include MP3s and exclude hidden backup folders.").font(.caption).foregroundStyle(.secondary)
            if let snapshot {
                HStack(spacing: 32) {
                    stat("Tracks", "\(ScanProgress.count(snapshot.tracks))")
                    stat("Artists", "\(ScanProgress.count(snapshot.artistCount))")
                    stat("Albums", "\(ScanProgress.count(snapshot.albumCount ?? 0))")
                    stat("Total Size", storage(snapshot.bytes))
                    stat("Unreadable Tags", "\(ScanProgress.count(snapshot.unreadable))")
                }
                if let skipped = snapshot.skippedSymbolicLinks, skipped > 0 {
                    Text("\(ScanProgress.count(skipped)) symbolic links skipped during discovery.").font(.caption).foregroundStyle(.secondary)
                }
                if let duration = snapshot.durationSeconds {
                    Text("Total duration: \(String(format: "%.1f hours", duration / 3600)) · Audio details unavailable: \(ScanProgress.count(snapshot.audioDetailsUnreadable ?? 0)) files").font(.caption)
                }
                HStack {
                    Text("Last complete update: \(snapshot.updated.formatted()) · \(ScanProgress.count(snapshot.reusedRecords ?? 0)) records reused · \(snapshot.databaseBacked == true ? "SQLite" : "JSON")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Review All Health Issues…") { m.reviewStatisticsHealth(snapshot) }.disabled((snapshot.findings == nil && snapshot.databaseBacked != true) || m.busy)
                }
                Text("Library Overview").font(.headline)
                HStack {
                    Picker("Group by", selection: $category) { Text("Artist").tag("Artist"); Text("Genre").tag("Genre"); Text("Year").tag("Year"); Text("Health").tag("Health"); if snapshot.bitrates != nil { Text("Bitrate").tag("Bitrate"); Text("Sample Rate").tag("Sample Rate") } }.pickerStyle(.segmented).labelsHidden()
                    TextField("Filter this view", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                if category == "Health" { Text("Select a row to review only that issue type.").font(.caption).foregroundStyle(.secondary) }
                Table(groups, selection: $selectedHealth, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Tracks", value: \.tracks) { Text("\(ScanProgress.count($0.tracks))") }.width(90)
                    TableColumn("Size", value: \.bytes) { Text(category == "Health" ? "—" : ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)) }.width(120)
                }
                .disabled(m.busy)
                .onChange(of: selectedHealth) { _, reason in
                    guard category == "Health", let reason, !m.busy else { return }
                    m.reviewStatisticsHealth(snapshot, reason: reason)
                }
                Text("Health counts are per issue and can overlap. Bitrate checks require audio statistics. Artist spellings remain distinct; missing fields are Unknown. Size includes tags and artwork.").font(.caption).foregroundStyle(.secondary)
            } else { ContentUnavailableView("No statistics for this library", systemImage: "chart.bar", description: Text("Choose Update Library Statistics to create a snapshot.")) }
            HStack { Spacer(); Button("Done") { dismiss() } }
        }.padding(24).frame(width: 930, height: 740)
            .sheet(isPresented: $m.showQuality, onDismiss: { selectedHealth = nil }) { QualityReviewView().environmentObject(m) }
            .onChange(of: category) { _, _ in
                selectedHealth = nil; query = ""
                sortOrder = [KeyPathComparator(\LibraryGroup.tracks, order: .reverse)]
            }
    }
    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(value).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
}
struct TechnicalView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var pictureID: Int?
    var picture: EmbeddedPicture? { m.pictures.first(where: { $0.id == pictureID }) ?? m.pictures.first(where: { $0.type == 3 }) ?? m.pictures.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Artwork & Technical Details").font(.title2.bold())
            HStack(alignment: .top, spacing: 24) {
                VStack {
                    if let picture, let image = NSImage(data: picture.data) { Image(nsImage: image).resizable().scaledToFit().frame(width: 240, height: 220) }
                    else { VStack { BrandWaveform().frame(width: 130, height: 55).opacity(0.4); Text("No artwork").foregroundStyle(.secondary) }.frame(width: 240, height: 220) }
                    if let picture { Text(ArtworkImage.details(picture.data)).font(.caption).textSelection(.enabled) }
                    if m.pictures.count > 1 {
                        Picker("Embedded picture", selection: Binding(get: { pictureID ?? picture?.id ?? 0 }, set: { pictureID = $0 })) {
                            ForEach(m.pictures) { entry in Text("\(entry.label) (\(entry.id + 1))").tag(entry.id) }
                        }
                    }
                    Button("Export Artwork…") { if let picture { m.exportArtwork(picture) } }.disabled(picture == nil)
                }.onDrop(of: [.fileURL], isTargeted: nil) { m.acceptArtworkDrop($0, batch: false) }
                ScrollView { Text(m.technical).textSelection(.enabled).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
            }
            ArtworkOptions().environmentObject(m)
            Text("Choose or drop a JPEG/PNG to replace the front cover. Other picture types are preserved unless Replace all is checked. Changes create full backups. Resize applies to the next image chosen or dropped.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Set Front Cover…") { m.changeArtwork() }
                Button("Resize Front Cover") { m.resizeFrontArtwork() }.disabled(m.artworkMaxEdge == 0 || !m.pictures.contains(where: { $0.type == 3 }))
                Button("Remove All Artwork") { m.changeArtwork(remove: true) }.disabled(m.pictures.isEmpty)
                Spacer(); Button("Done") { dismiss() }
            }
        }.padding(24).frame(width: 780, height: 530)
    }
}

struct FilenameDiffText: View {
    let before: String
    let after: String
    let proposed: Bool
    var body: some View {
        let segments = CharacterDiff.segments(before: before, after: after, proposed: proposed)
        segments.reduce(Text("")) { result, segment in
            result + (segment.1 ? Text(segment.0).foregroundColor(proposed ? .green : .red).bold() : Text(segment.0))
        }.textSelection(.enabled)
    }
}

struct AudioStatistics {
    static func read(_ original: LibrarySnapshot, root: URL, cancellation: JobCancellation, progress: (Int, Int) -> Void) async throws -> LibrarySnapshot {
        var snapshot = original
        let files = SourceFiles.mp3URLs(root: root, includeSubfolders: true, shouldCancel: { cancellation.isCancelled })
        var duration = 0.0, unreadable = 0
        var bitrates: [String: LibraryGroup] = [:], samples: [String: LibraryGroup] = [:]
        func add(_ name: String, bytes: Int64, to values: inout [String: LibraryGroup]) {
            var group = values[name] ?? LibraryGroup(name: name); group.tracks += 1; group.bytes += bytes; values[name] = group
        }
        for (index, url) in files.enumerated() {
            try cancellation.check()
            do {
                let asset = AVURLAsset(url: url)
                let seconds = try await asset.load(.duration).seconds
                guard seconds.isFinite, seconds >= 0 else { throw TagError(message: "Duration unavailable") }
                duration += seconds
                let track = try await asset.loadTracks(withMediaType: .audio).first
                let rate = try await track?.load(.estimatedDataRate) ?? 0
                let formats = try await track?.load(.formatDescriptions) ?? []
                let sampleRate = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate } ?? 0
                let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                add(rate > 0 ? "\(Int((rate / 1000).rounded())) kbps" : "Unknown", bytes: bytes, to: &bitrates)
                add(sampleRate > 0 ? "\(Int(sampleRate)) Hz" : "Unknown", bytes: bytes, to: &samples)
            } catch {
                unreadable += 1
                let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                add("Unknown", bytes: bytes, to: &bitrates); add("Unknown", bytes: bytes, to: &samples)
            }
            progress(index + 1, files.count)
        }
        try cancellation.check()
        snapshot.durationSeconds = duration; snapshot.audioDetailsUnreadable = unreadable
        snapshot.bitrates = bitrates.values.sorted { $0.tracks > $1.tracks }
        snapshot.sampleRates = samples.values.sorted { $0.tracks > $1.tracks }
        return snapshot
    }
}

struct JobErrorsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Operation Errors").font(.title2.bold())
            Text("Review these errors before retrying. Files changed since preview must be previewed again. Successful files are not repeated by Retry Failed.").font(.callout).foregroundStyle(.secondary)
            ScrollView { Text(m.lastErrors.joined(separator: "\n\n")).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Spacer(); Button("Done") { dismiss() } }
        }.padding(24).frame(width: 720, height: 480)
    }
}

@MainActor extension Model {
    func refreshInspectorArtwork() {
        let token = UUID(); inspectorArtworkToken = token
        let urls = selected.map(\.url)
        if urls.isEmpty { inspectorArtwork = .init(kind: "No files selected", count: 0); return }
        inspectorArtwork = .init(kind: "Loading artwork…", count: urls.count)
        Task {
            let result = await Task.detached { ArtworkSummary.read(urls) }.value
            if inspectorArtworkToken == token { inspectorArtwork = result }
        }
    }
    func refreshBatchArtwork() {
        let token = UUID(); batchArtworkToken = token
        let urls = batchCandidates.filter { batchTargets.contains($0.url) }.map(\.url)
        batchArtwork = .init(kind: urls.isEmpty ? "No files checked" : "Loading artwork…", count: urls.count)
        Task {
            let result = await Task.detached { ArtworkSummary.read(urls) }.value
            if batchArtworkToken == token { batchArtwork = result }
        }
    }
    func chooseBatchArtwork() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png,.jpeg]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 20_000_000, NSImage(data: data) != nil else { throw TagError(message: "Choose a valid JPEG or PNG smaller than 20 MB.") }
            batchArtworkData = try ArtworkImage.prepare(data, maxEdge: artworkMaxEdge); batchRemoveArtwork = false; batchApplyArtwork = true
        } catch { message = error.localizedDescription }
    }
}
struct ArtworkThumbnail: View {
    let summary: ArtworkSummary
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = summary.data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
                else if summary.kind.hasPrefix("Mixed") { Image(systemName: "square.stack").font(.title2).foregroundStyle(.secondary) }
                else { BrandWaveform().padding(6).opacity(0.35) }
            }.frame(width: 70, height: 70).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.kind).font(.caption).foregroundStyle(.secondary)
                if let data = summary.data { Text(ArtworkImage.details(data)).font(.caption2).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatisticsBrandLogo: View {
    var width: CGFloat = 160
    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandOriginal", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let original = NSBitmapImageRep(data: data)?.cgImage,
              let crop = original.cropping(to: CGRect(x: CGFloat(original.width) * 0.035,
                  y: CGFloat(original.height) * 0.19,
                  width: CGFloat(original.width) * 0.93,
                  height: CGFloat(original.height) * 0.545).integral) else { return nil }
        return NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
    }()
    var body: some View {
        VStack(spacing: width * 3 / 160) {
            if let mark = Self.mark {
                Image(nsImage: mark).resizable().interpolation(.high).scaledToFit()
                    .frame(width: width, height: width * 94 / 160)
            } else { Text("TagCraft").font(.title.bold()) }
            Text("MUSIC LIBRARIAN").font(.system(size: width * 9 / 160, weight: .medium))
                .tracking(width * 2.1 / 160).fixedSize().foregroundStyle(.primary)
        }.frame(width: width, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("TagCraft Music Librarian")
    }
}

struct BrandWaveform: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandOriginal", withExtension: "png"),
              let data = try? Data(contentsOf: url), let original = NSBitmapImageRep(data: data)?.cgImage,
              let crop = original.cropping(to: CGRect(x: (CGFloat(original.width) * 58 / 1254).rounded(),
                  y: (CGFloat(original.height) * 248 / 1254).rounded(),
                  width: (CGFloat(original.width) * 1137 / 1254).rounded(),
                  height: (CGFloat(original.height) * 453 / 1254).rounded())) else { return nil }
        return NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height))
    }()
    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct LibraryStructureView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LibraryStructure()
    private var validFolder: Bool {
        !draft.useIndividualFolder || (!draft.individualFolderName.isEmpty && LibraryPath.clean(draft.individualFolderName) == draft.individualFolderName && draft.individualFolderName != "." && draft.individualFolderName != "..")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Library Structure").font(.title2.bold())
            Toggle("Group artist folders by first letter or character", isOn: $draft.useLetterFolders)
            Text("Groups use A–Z, 0–9, or #. Turn this off to place artist folders directly in the library.").font(.caption).foregroundStyle(.secondary)
            Picker("Album tracks", selection: $draft.defaultPlacement) {
                Text("Organize into album folders under artist").tag(LibraryPlacement.albums)
                Text("Directly under artist").tag(LibraryPlacement.direct)
            }
            Text("Applies to files with an album tag. Album folder names come from that tag.").font(.caption).foregroundStyle(.secondary)
            Picker("Individual tracks (no album tag)", selection: $draft.useIndividualFolder) {
                Text("Directly under artist").tag(false)
                Text("Use a custom folder under artist").tag(true)
            }
            TextField("Custom individual tracks folder name", text: $draft.individualFolderName)
                .disabled(!draft.useIndividualFolder)
            Text("Choose any valid folder name, such as Individual Tracks, Singles, or - Singles.").font(.caption).foregroundStyle(.secondary)
            if !validFolder { Text("Enter a nonempty folder name without path separators or control characters.").font(.caption).foregroundStyle(.red) }
            Text("Move to Library follows both rules automatically and offers a placement override for each operation. Workflows use these defaults.").foregroundStyle(.secondary)
            Text("These settings affect future moves only. Existing library files are not reorganized.").font(.callout)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { m.libraryStructure = draft; dismiss() }.buttonStyle(.borderedProminent).disabled(!validFolder).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 640)
            .onAppear { draft = m.libraryStructure; if draft.defaultPlacement != .albums { draft.defaultPlacement = .direct } }
    }
}
