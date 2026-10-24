import SwiftUI
import AppKit
import AVFoundation

enum AppPreferences {
    static let defaults: UserDefaults = {
        #if TAGCRAFT_UI_CHECKS
        // Test models and previews must never migrate or modify Nate's settings.
        return UserDefaults(suiteName: "local.tagcraft.ui-check." + UUID().uuidString)!
        #else
        // An explicitly named suite is independent of executable names and versions.
        let defaults = UserDefaults(suiteName: "local.tagcraft.musiclibrarian.preferences")!
        if !defaults.bool(forKey: "didMigrateStablePreferences") {
            let current = UserDefaults.standard
            let domains = [current.persistentDomain(forName: "local.tagcraft.musiclibrarian") ?? [:],
                           current.persistentDomain(forName: "local.trackshelf.app") ?? [:]]
            for key in ["library", "lastMusicFolder", "recentFolders", "purgeFields", "ignoreParentheses", "ignoreBraces", "ignoreBrackets", "showActionText", "inspectorWidth"] {
                if defaults.object(forKey: key) == nil,
                   let value = current.object(forKey: key) ?? domains.compactMap({ $0[key] }).first {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: "didMigrateStablePreferences")
            defaults.synchronize()
        }
        return defaults
        #endif
    }()
}

struct Track: Identifiable {
    var id: URL { url }
    var url: URL
    var tags: Tags
    var issue: String?
    var filename: String { url.lastPathComponent }
    var artist: String { tags.artist }
    var title: String { tags.title }
    var album: String { tags.album }
    var trackNumber: String { tags.track }
    var year: String { tags.year }
    var albumArtistColumn: String { tags.value("Album Artist") }
    var discColumn: String { tags.value("Disc") }
    var composerColumn: String { tags.value("Composer") }
    var conductorColumn: String { tags.value("Conductor") }
    var bpmColumn: String { tags.value("BPM") }
    var publisherColumn: String { tags.value("Publisher") }
    var copyrightColumn: String { tags.value("Copyright") }
    var encodedByColumn: String { tags.value("Encoded By") }
    var languageColumn: String { tags.value("Language") }
    var groupingColumn: String { tags.value("Grouping") }
    var subtitleColumn: String { tags.value("Subtitle") }
    var isrcColumn: String { tags.value("ISRC") }
    var lyricistColumn: String { tags.value("Lyricist") }
    var lyricsColumn: String { tags.value("Lyrics") }
    var genreColumn: String { tags.value("Genre") }
    var status: String { issue == nil ? "Ready" : "Read only" }
}
struct MoveItem: Identifiable {
    var statusText: String? = nil
    var id: URL { source }
    let source: URL
    let destination: URL?
    let issue: String?
    var warning: String? = nil
    var detail: String? = nil
}
@MainActor final class Model: ObservableObject {
    @Published var noticeAcknowledged = LicenseAcceptance.isAcknowledged(defaults: AppPreferences.defaults, release: AppRelease.noticeRelease)
    @Published var showReadTerms = false
    @Published var showInspectorDisplaySettings = false
    @Published var showColumnSettings = false
    @Published var columnFitRequest = UUID()
    func autoFitColumns() { columnFitRequest = UUID() }
    @Published var inspectorDisplayedFields = TagVisibility.load("inspectorDisplayedFields", defaults: AppPreferences.defaults, fallback: Set(TagVisibility.tags), allowed: Set(TagVisibility.tags)) {
        didSet { AppPreferences.defaults.set(inspectorDisplayedFields.sorted(), forKey: "inspectorDisplayedFields") }
    }
    @Published var workspaceColumns = TagVisibility.load("workspaceColumns", defaults: AppPreferences.defaults, fallback: TagVisibility.defaultColumns, allowed: TagVisibility.columnChoices).union(["Filename"]) {
        didSet { AppPreferences.defaults.set(workspaceColumns.sorted(), forKey: "workspaceColumns") }
    }

    @Published var tracks: [Track] = []
    @Published var selection = Set<URL>()
    @Published var folder: URL?
    @Published var library: URL?
    @Published var query = ""
    @Published var includeSubfolders = false
    @Published var sortOrder = [KeyPathComparator(\Track.filename, comparator: .localizedStandard)]
    @Published var draft = Tags()
    @Published var baseline = Tags()
    @Published var inspectorMixed = Set<String>()
    @Published var inspectorFields = Set<String>()
    @Published var inspectorCleared = Set<String>()
    var inspectorTracksIntent = false
    @Published var batchCleared = Set<String>()
    @Published var message = ""
    @Published var moves: [MoveItem] = []
    @Published var showUpdateCheck = false
    @Published var showAbout = false
    @Published var showLibraryStructure = false
    @Published var movePlacement = LibraryPlacement.settings
    @Published var libraryStructure: LibraryStructure = SettingsFiles.load("library-structure.json") ?? LibraryStructure() {
        didSet { SettingsFiles.save(libraryStructure, "library-structure.json") }
    }
    @Published var showPurgeSettings = false
    @Published var purgeFields = Set(AppPreferences.defaults.stringArray(forKey: "purgeFields") ?? []) {
        didSet { AppPreferences.defaults.set(Array(purgeFields), forKey: "purgeFields") }
    }
    var purgeFrameIDs: Set<String> {
        PurgeField.fields.filter { purgeFields.contains($0.id) }.reduce(into: Set<String>()) { $0.formUnion($1.frames) }
    }
    var purgeDescriptions: [URL: String] = [:]
    var previewPurgeFrameIDs = Set<String>()
    @Published var showMoves = false
    @Published var renameLayout = "Artist - Title"
    @Published var renameCustomMask = "{Artist} - {Title}"
    var renameMask: String {
        if let index = FilenameMask.presets.firstIndex(of: renameLayout), index < 3 { return FilenameMask.masks[index] }
        return renameCustomMask
    }
    @Published var ignoreParentheses = AppPreferences.defaults.bool(forKey: "ignoreParentheses") {
        didSet { AppPreferences.defaults.set(ignoreParentheses, forKey: "ignoreParentheses") }
    }
    @Published var ignoreBraces = AppPreferences.defaults.bool(forKey: "ignoreBraces") {
        didSet { AppPreferences.defaults.set(ignoreBraces, forKey: "ignoreBraces") }
    }
    @Published var ignoreBrackets = AppPreferences.defaults.bool(forKey: "ignoreBrackets") {
        didSet { AppPreferences.defaults.set(ignoreBrackets, forKey: "ignoreBrackets") }
    }
    var ignoredGroups: Set<String> {
        var groups = Set<String>()
        if ignoreParentheses { groups.insert("()") }
        if ignoreBraces { groups.insert("{}") }
        if ignoreBrackets { groups.insert("[]") }
        return groups
    }
    @Published var extractionLayout = "Artist - Title"
    @Published var customMask = "{Artist} - {Title}"
    var extractionMask: String {
        if let index = FilenameMask.presets.firstIndex(of: extractionLayout), index < 3 { return FilenameMask.masks[index] }
        return customMask
    }
    @Published var showBatch = false
    @Published var batchTargets = Set<URL>()
    @Published var batchFields = Set<String>()
    @Published var batchMixed = Set<String>()
    @Published var batchDraft = Tags()
    var batchCandidates: [Track] = []
    var extractedTags: [URL: Tags] = [:]
    @Published var operation = "Move to Library"
    @Published var busy = false
    @Published var showCleanSettings = false
    @Published var showWorkflow = false
    @Published var showMagicReview = false
    @Published var magicSuggestions: [MagicSuggestion] = []
    @Published var showStatistics = false
    @Published var includeAudioStatistics = false
    @Published var showTechnical = false
    @Published var cleanRules: CleanRules = SettingsFiles.load("clean-rules.json") ?? CleanRules() {
        didSet { SettingsFiles.save(cleanRules, "clean-rules.json") }
    }
    @Published var workflows: [WorkflowPreset] = SettingsFiles.load("workflows.json") ?? []
    @Published var workflow = WorkflowPreset()
    @Published var planned: [URL: FilePlan] = [:]
    @Published var excluded = Set<URL>()
    @Published var progressDone = 0
    @Published var progressTotal = 0
    @Published var progressText = ""
    @Published var failures: [FilePlan] = []
    @Published var lastErrors: [String] = []
    @Published var showJobErrors = false
    @Published var recentFolders: [String] = AppPreferences.defaults.stringArray(forKey: "recentFolders") ?? []
    @Published var autoRefresh = false
    @Published var reuseStatistics = true
    @Published var showQuality = false
    @Published var qualityFindings: [QualityFinding] = []
    @Published var qualityRoot = "Workspace"
    @Published var qualityDate: Date?
    @Published var qualityMessage = ""
    @Published var qualityReason = ""
    @Published var qualityAvailableReasons: [String] = []
    @Published var qualityLoading = false
    var qualityScopeSnapshot: LibrarySnapshot?
    var qualityReloadToken = UUID()
    @Published var stats: LibrarySnapshot?
    @Published var statisticsReady = false
    @Published var statisticsLoading = false
    @Published var statisticsError = ""
    var statisticsRestoreStarted = false
    var statisticsStore: LibraryStore?
    @Published var technical = ""
    @Published var inspectorArtwork = ArtworkSummary(kind: "No files selected", count: 0)
    @Published var batchArtwork = ArtworkSummary(kind: "No files selected", count: 0)
    @Published var batchArtworkData: Data?
    @Published var batchApplyArtwork = false
    @Published var batchRemoveArtwork = false
    var inspectorArtworkToken = UUID()
    var batchArtworkToken = UUID()
    @Published var pictures: [EmbeddedPicture] = []
    @Published var artworkMaxEdge = 0
    @Published var replaceAllArtwork = false
    @Published var artwork: NSImage?
    @Published var artistNames: [String] = []
    @Published var artistSuggestions: [URL: [String]] = [:]
    @Published var artistChoices: [URL: String] = [:]
    @Published var duplicateSummary = ""
    @Published var duplicateResults: [URL: String] = [:]
    var cancellation = JobCancellation()
    var runningTask: Task<Void, Never>?
    var folderMonitor: FolderMonitor?
    var previewFingerprints: [URL: (Int?, Date?)] = [:]
    let playback = PlaybackController()
    @Published var undoMoves: [(URL,URL)] = []
    @Published var undoRevision = 0
    weak var fileUndoManager: UndoManager?
    var undoObservers: [NSObjectProtocol] = []
    var undoTracks: [URL: Track] = [:]
    var scanToken = UUID()
    var selected: [Track] { tracks.filter { selection.contains($0.url) } }
    var filtered: [Track] { tracks.filter { query.isEmpty || "\($0.filename) \($0.tags.artist) \($0.tags.album) \($0.tags.title)".localizedCaseInsensitiveContains(query) }.sorted(using: sortOrder) }
    @Published var showActionText = AppPreferences.defaults.object(forKey: "showActionText") as? Bool ?? true {
        didSet { AppPreferences.defaults.set(showActionText, forKey: "showActionText") }
    }
    var eligibleMoves: [MoveItem] { moves.filter { $0.issue == nil && !excluded.contains($0.source) } }
    private var restoredMusicFolder = false
    var inspectorPatch: TagEditPatch {
        let inferred = Set(TagEditPatch.fields.filter { draft.value($0) != baseline.value($0) })
        return TagEditPatch(draft: draft, checked: inspectorTracksIntent ? inspectorFields : inferred, cleared: inspectorCleared)
    }
    var batchPatch: TagEditPatch { TagEditPatch(draft: batchDraft, checked: batchFields, cleared: batchCleared) }
    var dirty: Bool { !inspectorPatch.effective.isEmpty }
    func restoreMusicFolder() {
        guard noticeAcknowledged, !restoredMusicFolder else { return }
        restoredMusicFolder = true
        let session: WorkspaceSession? = SettingsFiles.load("workspace-session.json")
        guard folder == nil, let path = AppPreferences.defaults.string(forKey: "lastMusicFolder") ?? session?.workspace else { return }
        let url = URL(fileURLWithPath: path)
        openFolder(url)
    }
    init() {
        let session: WorkspaceSession? = SettingsFiles.load("workspace-session.json")
        if let path = AppPreferences.defaults.string(forKey: "library") ?? session?.library { library = URL(fileURLWithPath: path) }
        if AppPreferences.defaults.object(forKey: "recentFolders") == nil { recentFolders = session?.recentWorkspaces ?? [] }
        playback.queue = { [weak self] in self?.filtered.map(PlaybackTrack.init) ?? [] }
    }
    func pick(library isLibrary: Bool = false) {
        guard noticeAcknowledged, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = isLibrary ? "Choose your organized music library" : "Open a TagCraft workspace folder containing files to edit"
        panel.prompt = isLibrary ? "Choose Library" : "Open Workspace"
        if isLibrary {
            panel.directoryURL = library
            let label = NSTextField(labelWithString: "Current location:")
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            let path = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 54))
            path.string = library?.path ?? "No library selected"
            path.isEditable = false; path.isSelectable = true; path.drawsBackground = false
            path.font = .systemFont(ofSize: 12)
            path.textContainer?.widthTracksTextView = true
            path.textContainer?.lineBreakMode = .byCharWrapping
            path.isVerticallyResizable = true
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 60))
            scroll.documentView = path; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: 600), scroll.heightAnchor.constraint(equalToConstant: 60)])
            let accessory = NSStackView(views: [label, scroll])
            accessory.orientation = .vertical; accessory.alignment = .leading; accessory.spacing = 4
            panel.accessoryView = accessory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if isLibrary { library = url; AppPreferences.defaults.set(url.path, forKey: "library"); saveSession(); refreshStoredStatistics(); scan() }
        else { openFolder(url) }
    }
    func scan() {
        guard noticeAcknowledged, !busy, let folder else { return }
        guard !dirty else { message = "Save or discard inspector edits before refreshing the workspace."; return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue,
              FileManager.default.isReadableFile(atPath: folder.path) else {
            scanToken = UUID(); busy = false; tracks = []; selection = []; loadSelection()
            message = "Music folder is unavailable or unreadable: " + folder.path + ". Use Open Workspace to choose another folder, or reconnect it and Refresh."
            return
        }
        let token = UUID()
        scanToken = token
        let includeSubfolders = includeSubfolders
        busy = true
        progressText = "Scanning music folder"; progressDone = 0; progressTotal = 0
        cancellation = JobCancellation()
        let cancel = cancellation
        runningTask = Task {
            let scanResult = await Task.detached { () -> ([Track], Int) in
                var result: [Track] = [], skipped = 0
                for url in SourceFiles.mp3URLs(root: folder, includeSubfolders: includeSubfolders, shouldCancel: { cancel.isCancelled }, skippedLink: { skipped += 1 }) {
                    if cancel.isCancelled { break }
                    do { let data = try Data(contentsOf: url, options: .mappedIfSafe); let id3 = try ID3(data); result.append(Track(url: url, tags: id3.tags)) }
                    catch { result.append(Track(url: url, tags: Tags(), issue: error.localizedDescription)) }
                    if result.count % 25 == 0 { let count = result.count; Task { @MainActor in self.progressDone = count; self.progressText = "Read \(count) tracks" } }
                }
                return (result.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }, skipped)
            }.value
            let result = scanResult.0
            guard token == scanToken else { return }
            if cancel.isCancelled { busy = false; message = "Scan cancelled; previous listing retained."; return }
            tracks = result; selection = []; draft = Tags(); baseline = draft; busy = false
            message = "\(tracks.count) MP3 files found" + (includeSubfolders ? " in this folder and its subfolders." : " in this folder.") + (scanResult.1 > 0 ? " \(ScanProgress.count(scanResult.1)) symbolic links skipped." : "")
        }
    }
    var hiddenSelection: Set<URL> { selection.subtracting(Set(filtered.map(\.url))) }
    var selectionSummary: String {
        "\(selection.count) selected" + (hiddenSelection.isEmpty ? "" : ", including \(hiddenSelection.count) hidden by the filter")
    }
    func requestSelection(_ next: Set<URL>) {
        guard !busy, next != selection else { return }
        guard dirty else { selection = next; return }
        let alert = NSAlert()
        alert.messageText = "Save tag changes before changing selection?"
        alert.informativeText = "Your selected files have unsaved edits. Save writes those edits; Discard changes only the selection without saving."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save(onSuccess: { [weak self] in self?.selection = next; self?.loadSelection() })
        case .alertSecondButtonReturn: selection = next
        default: break
        }
    }
    func confirmHiddenScope(_ urls: Set<URL>, action: String) -> Bool {
        let hidden = urls.intersection(hiddenSelection)
        guard !hidden.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Include files hidden by the filter?"
        alert.informativeText = "\(action): \(urls.count) in scope; \(hidden.count) hidden by the filter. Cancel to clear the filter and review the full selection first."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Include Hidden Files")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func loadSelection() {
        draft = Tags(); inspectorMixed = []; inspectorFields = []; inspectorCleared = []; inspectorTracksIntent = false
        for name in TagEditPatch.fields {
            let common = MixedTagValues.value(name, in: selected.map(\.tags))
            draft.set(name, common.value)
            if common.mixed { inspectorMixed.insert(name) }
        }
        baseline = draft
        refreshInspectorArtwork()
    }
    func save(overrides: [URL: Tags]? = nil, artworkData: Data? = nil, removeArtwork: Bool = false, onSuccess: (() -> Void)? = nil) {
        guard !busy else { return }
        let patch = inspectorPatch
        if overrides == nil && !confirmTagRemoval(patch, count: selected.count) { return }
        let plans = selected.compactMap { track -> FilePlan? in
            let tags = overrides?[track.url] ?? patch.applying(to: track.tags)
            guard tags != track.tags || artworkData != nil || removeArtwork else { return nil }
            let stamp = FileJobs.fingerprint(track.url)
            return FilePlan(source: track.url, destination: track.url, tags: tags, artwork: artworkData, removeArtwork: removeArtwork, replaceAllArtwork: replaceAllArtwork, expectedSize: stamp.0, expectedDate: stamp.1)
        }
        if plans.isEmpty { loadSelection(); onSuccess?(); return }
        runPlans(plans, label: "Save Tags", completion: { success in if success { onSuccess?() } })
    }
    func beginBatch() {
        guard !busy else { return }
        batchCandidates = selected
        batchTargets = selection
        batchFields = []; batchCleared = []
        batchArtworkData = nil; batchApplyArtwork = false; batchRemoveArtwork = false
        refreshBatchArtwork()
        refreshBatchValues()
        showBatch = true
    }
    func applyBatch() {
        let patch = batchPatch
        guard confirmTagRemoval(patch, count: batchTargets.count) else { return }
        let inputs = batchCandidates.filter { batchTargets.contains($0.url) }
        let plans = inputs.compactMap { track -> FilePlan? in
            let tags = patch.applying(to: track.tags)
            let artwork = batchApplyArtwork && !batchRemoveArtwork ? batchArtworkData : nil
            let remove = batchApplyArtwork && batchRemoveArtwork
            guard tags != track.tags || artwork != nil || remove else { return nil }
            let stamp = FileJobs.fingerprint(track.url)
            return FilePlan(source: track.url, destination: track.url, tags: tags, artwork: artwork, removeArtwork: remove, replaceAllArtwork: replaceAllArtwork, expectedSize: stamp.0, expectedDate: stamp.1)
        }
        guard !plans.isEmpty else { message = "No tag changes to apply."; return }
        runPlans(plans, label: "Edit ALL Tags", completion: { [weak self] success in if success { self?.showBatch = false } })
    }
    func confirmTagRemoval(_ patch: TagEditPatch, count: Int) -> Bool {
        guard !patch.effective.intersection(patch.cleared).isEmpty else { return true }
        let alert = NSAlert(); alert.messageText = "Remove the selected tags?"
        alert.informativeText = "Selected tracks: \(count)\n" + patch.summary + "\nOther fields are preserved. Full file backups are created."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Apply Tag Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func editTagField(_ name: String, value: String, batch: Bool) {
        let previous = (batch ? batchDraft : draft).value(name)
        guard value != previous else { return }
        let blank = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let erased = blank && !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if batch {
            batchDraft.set(name, value)
            if !blank { batchFields.insert(name); batchCleared.remove(name) }
            else if erased || batchCleared.contains(name) { batchFields.insert(name); batchCleared.insert(name) }
            else { batchFields.remove(name) }
        } else {
            inspectorTracksIntent = true; draft.set(name, value)
            if !blank { inspectorFields.insert(name); inspectorCleared.remove(name) }
            else if erased || inspectorCleared.contains(name) { inspectorFields.insert(name); inspectorCleared.insert(name) }
            else { inspectorFields.remove(name) }
        }
    }
    func checkTagField(_ name: String, enabled: Bool, batch: Bool) {
        if batch {
            if enabled { batchFields.insert(name) } else { batchFields.remove(name); batchCleared.remove(name) }
        } else {
            inspectorTracksIntent = true
            if enabled { inspectorFields.insert(name) } else { inspectorFields.remove(name); inspectorCleared.remove(name) }
        }
    }
    func clearCheckedTags(batch: Bool) {
        if batch { batchCleared = batchFields; for name in batchFields { batchDraft.set(name, "") } }
        else { inspectorTracksIntent = true; inspectorCleared = inspectorFields; for name in inspectorFields { draft.set(name, "") } }
    }
    func previewPurge() {
        guard !busy else { return }
        guard !purgeFrameIDs.isEmpty else { showPurgeSettings = true; return }
        operation = "Purge Tags"
        previewPurgeFrameIDs = purgeFrameIDs
        let ids = previewPurgeFrameIDs, inputs = selected
        busy = true; cancellation = JobCancellation(); let cancel = cancellation
        progressText = "Preparing purge preview"; progressDone = 0; progressTotal = inputs.count
        runningTask = Task {
            let result = await Task.detached { () -> ([MoveItem], [URL: String]) in
                var rows: [MoveItem] = [], descriptions: [URL: String] = [:]
                for (index, track) in inputs.enumerated() {
                    if cancel.isCancelled { break }
                    do {
                        let data = try Data(contentsOf: track.url, options: .mappedIfSafe)
                        let parsed = try ID3(data)
                        let present = Set(parsed.frames.map(\.id)).union(ID3.legacyFields(data)).intersection(ids)
                        guard !present.isEmpty else { throw TagError(message: "None of the configured tags are present. No change needed.") }
                        let names = PurgeField.fields.filter { !$0.frames.intersection(present).isEmpty }.map(\.id)
                        descriptions[track.url] = "Will remove: " + names.joined(separator: ", ")
                        rows.append(.init(source: track.url, destination: nil, issue: nil))
                    } catch { rows.append(.init(source: track.url, destination: nil, issue: error.localizedDescription)) }
                    Task { @MainActor in self.progressDone = index + 1 }
                }
                return (rows, descriptions)
            }.value
            busy = false
            if cancel.isCancelled { message = "Purge preview cancelled; no files changed."; return }
            moves = result.0; purgeDescriptions = result.1; showMoves = true
        }
    }
    func executePurge() {
        runPlans(eligibleMoves.map { item in
            let stamp = previewFingerprints[item.source] ?? FileJobs.fingerprint(item.source)
            return FilePlan(source: item.source, destination: item.source, purge: previewPurgeFrameIDs, expectedSize: stamp.0, expectedDate: stamp.1)
        }, label: "Purge Tags")
    }
    func previewClean() {
        guard !busy else { return }
        operation = "Clean Filenames"
        var destinations = Set<String>()
        moves = selected.map { track in
            let name: String
            do { name = try cleanRules.clean(track.filename, tags: track.tags).0 }
            catch { return MoveItem(source: track.url, destination: nil, issue: error.localizedDescription) }
            let destination = track.url.deletingLastPathComponent().appendingPathComponent(name)
            let key = destination.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let same = destination.path == track.url.path
            let conflict = !same && FileJobs.destinationConflict(source: track.url, destination: destination)
            let duplicate = !destinations.insert(key).inserted
            let issue: String? = same ? "Already clean." : ((conflict || duplicate) ? "Destination filename conflict." : nil)
            return MoveItem(source: track.url, destination: destination, issue: issue, warning: (try? cleanRules.clean(track.filename, tags: Tags()).1).flatMap { $0.contains(where: { $0.contains("unspaced hyphen") }) ? "Review inferred separators; meaningful hyphens may need an exception." : nil }, detail: (try? cleanRules.clean(track.filename, tags: Tags()).1.joined(separator: " · ")))
        }
        showMoves = true
    }
    func previewRename() {
        guard !busy else { return }
        operation = "Rename Files from Tags"
        var destinations = Set<String>()
        moves = selected.map { track in
            do {
                if let issue = track.issue { throw TagError(message: issue) }
                let name = try FilenameTemplate(renameMask).filename(tags: track.tags)
                let destination = track.url.deletingLastPathComponent().appendingPathComponent(name)
                let key = destination.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let duplicate = !destinations.insert(key).inserted
                let same = destination.path == track.url.path
                let issue: String? = same ? "Already named correctly." : ((duplicate || FileJobs.destinationConflict(source: track.url, destination: destination)) ? "Destination filename conflict." : nil)
                return MoveItem(source: track.url, destination: destination, issue: issue)
            } catch { return MoveItem(source: track.url, destination: nil, issue: error.localizedDescription) }
        }
        showMoves = true
    }
    func previewExtract() {
        guard !busy else { return }
        operation = "Get Tags from Filename"
        extractedTags = [:]
        moves = selected.map { track in
            do {
                if let issue = track.issue { throw TagError(message: issue) }
                let parser = try FilenameMask(extractionMask, ignoredGroups: ignoredGroups)
                let tags = try parser.extract(track.filename, existing: track.tags)
                extractedTags[track.url] = tags
                return MoveItem(source: track.url, destination: nil, issue: nil, warning: parser.review(track.filename).warning)
            } catch { return MoveItem(source: track.url, destination: nil, issue: error.localizedDescription) }
        }
        showMoves = true
    }
    func applyPreview() {
        if operation == "Preparation Workflow" { runPlans(eligibleMoves.compactMap { planned[$0.source] }, label: workflow.name); return }
        if operation == "Purge Tags" { executePurge(); return }
        if operation == "Get Tags from Filename" {
            // Limit saving to valid preview rows; preserve all other fields.
            let plans = eligibleMoves.compactMap { item -> FilePlan? in
                guard let tags = extractedTags[item.source] else { return nil }
                let stamp = previewFingerprints[item.source] ?? FileJobs.fingerprint(item.source)
                return FilePlan(source: item.source, destination: item.source, tags: tags, expectedSize: stamp.0, expectedDate: stamp.1)
            }
            runPlans(plans, label: "Get Tags from Filename")
        } else { executeMove() }
    }
    func previewDescription(_ item: MoveItem) -> String {
        if let issue = item.issue { return issue }
        if operation == "Purge Tags" { return purgeDescriptions[item.source] ?? "" }
        if operation == "Get Tags from Filename", let tags = extractedTags[item.source] {
            let names = (try? FilenameMask(extractionMask, ignoredGroups: ignoredGroups).captures) ?? []
            let original = tracks.first(where: { $0.url == item.source })?.tags ?? Tags()
            var parts = names.filter { $0 != "Skip" }.map { "\($0): \(original.value($0).isEmpty ? "(empty)" : original.value($0)) → \(tags.value($0))" }
            if let parser = try? FilenameMask(extractionMask, ignoredGroups: ignoredGroups) {
                parts += parser.review(item.source.lastPathComponent).ignored.map { "Ignored: \($0)" }
            }
            return parts.joined(separator: "    •    ")
        }
        return item.destination?.path ?? ""
    }
    func previewMove() {
        guard !busy else { return }
        operation = "Move to Library"
        guard let library else { pick(library: true); return }
        var destinations = Set<String>()
        moves = selected.map { track in
            do {
                if let issue = track.issue { throw TagError(message: issue) }
                let destination = try LibraryPath.destination(root: library, artist: artistChoices[track.url] ?? track.tags.artist, filename: track.filename, album: track.tags.album, structure: libraryStructure, placement: movePlacement)
                let key = destination.path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                guard destination.standardizedFileURL != track.url.standardizedFileURL else { throw TagError(message: "Already in this library location.") }
                guard !FileJobs.destinationConflict(source: track.url, destination: destination), destinations.insert(key).inserted else { throw TagError(message: "Destination filename conflict.") }
                let matching = duplicateResults[track.url].map { "Matching audio already in library: " + $0 }
                return MoveItem(source: track.url, destination: destination, issue: nil, warning: matching)
            } catch { return MoveItem(source: track.url, destination: nil, issue: error.localizedDescription) }
        }
        showMoves = true
    }
    func executeMove() {
        let plans = eligibleMoves.compactMap { item -> FilePlan? in
            guard let destination = item.destination else { return nil }
            let stamp = previewFingerprints[item.source] ?? FileJobs.fingerprint(item.source)
            return FilePlan(source: item.source, destination: destination, expectedSize: stamp.0, expectedDate: stamp.1)
        }
        runPlans(plans, label: operation)
    }
    func undoMove() { guard !busy else { return }; fileUndoManager?.undo() }
    func play() {
        guard let track = filtered.first(where: { selection.contains($0.url) }) else { return }
        playback.play(PlaybackTrack(track))
    }
}

#if !TAGCRAFT_UI_CHECKS
@main struct TagCraftApp: App {
    @NSApplicationDelegateAdaptor(LaunchDelegate.self) private var launchDelegate
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("TagCraft Music Librarian") {
            LicenseGateRoot().environmentObject(model).frame(minWidth: 1050, minHeight: 620)
                .background(LaunchWindowGate()).onAppear { launchDelegate.model = model }
        }.windowStyle(.titleBar)
        Settings { LicenseGateRoot(settings: true).environmentObject(model) }
        .commands {
            WorkspaceCommands(model: model)
            CommandGroup(replacing: .appInfo) {
                Button("About TagCraft…") { model.showAbout = true }.disabled(!model.noticeAcknowledged)
                Button("Check for Updates…") { model.showUpdateCheck = true }.disabled(!model.noticeAcknowledged)
                Button("License & Usage Notice…") { model.showReadTerms = true }.disabled(!model.noticeAcknowledged)
            }
        }
    }
}
#endif
final class SelectionHeader: NSTableHeaderView {
    var toggleAll: (() -> Void)?
    // Keep divider hit testing with AppKit; only the selection header's interior toggles.
    func isSelectionClick(_ point: NSPoint) -> Bool {
        guard column(at: point) == 0 else { return false }
        return point.x < headerRect(ofColumn: 0).maxX - 6
    }
    override func mouseDown(with event: NSEvent) {
        if isSelectionClick(convert(event.locationInWindow, from: nil)) {
            toggleAll?()
        } else { super.mouseDown(with: event) }
    }
}
final class ToolbarAnchor: NSView {
    var lastColumnFitRequest: UUID?
    var configureTable: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didUpdateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowUpdated), name: NSWindow.didUpdateNotification, object: window)
        }
        DispatchQueue.main.async {
            self.configureTable?()
        }
    }
    @objc private func windowUpdated(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.configureTable?() }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
struct ToolbarDefaults: NSViewRepresentable {
    var model: Model
    var toggleAll: () -> Void
    var allSelected: Bool
    func makeNSView(context: Context) -> NSView {
        let view = ToolbarAnchor()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        let configure: () -> Void = { [weak view] in
            guard let view else { return }
            if let manager = view.window?.undoManager { model.installUndoManager(manager) }
            func findTable(_ root: NSView) -> NSTableView? {
                if let table = root as? NSTableView, table.tableColumns.first?.title == "✓" || table.tableColumns.first?.title == "☐" || table.tableColumns.first?.title == "☑" { return table }
                for child in root.subviews { if let table = findTable(child) { return table } }
                return nil
            }
            guard let root = view.window?.contentView, let table = findTable(root),
                  let anchor = view as? ToolbarAnchor else { return }
            let selectionTitle = allSelected ? "☑" : "☐"
            let needsConfiguration = !(table.headerView is SelectionHeader)
                || table.columnAutoresizingStyle != .noColumnAutoresizing
                || anchor.lastColumnFitRequest != model.columnFitRequest
                || table.tableColumns.first?.title != selectionTitle
                || table.tableColumns.dropFirst().contains { column in
                    column.isHidden != (column.title != "Filename" && !model.workspaceColumns.contains(column.title))
                    || column.resizingMask != .userResizingMask
                }
            // Window updates occur after SwiftUI has reconciled its native table.
            // Do nothing when already configured, avoiding a redraw/update loop.
            guard needsConfiguration else { return }
            let header: SelectionHeader
            if let existing = table.headerView as? SelectionHeader { header = existing }
            else {
                header = SelectionHeader(frame: table.headerView?.frame ?? .zero)
                table.headerView = header
                header.toolTip = "Click the selection header to select or deselect all visible tracks. Click data headers to sort."
            }
            header.toggleAll = toggleAll
            // Native visibility supports macOS 14.0; conditional SwiftUI columns require 14.4.
            // The SwiftUI definitions retain stable column identities and sorting.
            WorkspaceTableLayout.configure(table, visible: model.workspaceColumns)
            if let anchor = view as? ToolbarAnchor {
                if anchor.lastColumnFitRequest != model.columnFitRequest {
                    WorkspaceTableLayout.fit(table, tracks: model.filtered)
                }
                anchor.lastColumnFitRequest = model.columnFitRequest
            }
            table.tableColumns.first?.title = allSelected ? "☑" : "☐"
            header.needsDisplay = true
        }
        (view as? ToolbarAnchor)?.configureTable = configure
        DispatchQueue.main.async(execute: configure)
    }
}
struct QuickHint: ViewModifier {
    let text: String
    @State private var hovered = false
    @State private var visible = false
    @State private var mouseMonitor: Any?
    func body(content: Content) -> some View {
        content.onHover { inside in
            hovered = inside
            if !inside { visible = false }
        }
        .task(id: hovered) {
            guard hovered else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            if !Task.isCancelled { visible = true }
        }
        .overlay(alignment: .bottom) {
            if visible {
                Text(text).font(.callout).padding(9)
                    .fixedSize(horizontal: false, vertical: true).frame(width: 270)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 3, y: 2)
                    .offset(y: 64)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(visible ? 1000 : 0)
        .onAppear {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
                visible = false; hovered = false
                return event
            }
        }
        .onDisappear {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil; visible = false
        }
        .accessibilityHint(text)
    }
}
extension View {
    func quickHint(_ text: String) -> some View { modifier(QuickHint(text: text)) }
}
struct PurgeSettingsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MP3 Tags to Purge").font(.title2.bold())
            Text("Choose fields for the Purge action. These settings are saved; nothing is deleted here. All instances of each chosen field are removed, including multiple artwork or comment frames.").foregroundStyle(.secondary)
            HStack {
                Button("Select All") { m.purgeFields = Set(PurgeField.fields.map(\.id)) }
                Button("Select None") { m.purgeFields = [] }
            }
            List(PurgeField.fields) { field in
                Toggle(field.id, isOn: Binding(get: { m.purgeFields.contains(field.id) }, set: { enabled in
                    if enabled { m.purgeFields.insert(field.id) } else { m.purgeFields.remove(field.id) }
                })).help(field.frames.sorted().joined(separator: ", "))
            }
            Text("Applies to supported ID3v2.3/v2.4 frames. Corresponding legacy ID3v1 fields are cleared too. Backups are made before each purge.").font(.caption).foregroundStyle(.secondary)
            HStack { Text("\(m.purgeFields.count) fields selected").font(.caption); Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(minWidth: 580, idealWidth: 580, maxWidth: .infinity, minHeight: 480, idealHeight: 600, maxHeight: .infinity).background(ResizableReviewSheet())
    }
}
struct ActionBarLabel: LabelStyle {
    var showText: Bool
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            configuration.icon.font(.system(size: 18)).frame(height: 28)
            if showText { configuration.title.font(.system(size: 12)).lineLimit(1) }
        }.padding(.horizontal, 4).frame(minHeight: 48)
            .contentShape(Rectangle())
    }
}
struct BrandWordmark: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandOriginal", withExtension: "png"),
              let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data), let original = rep.cgImage else { return nil }
        let bounds = CGRect(x: CGFloat(original.width) * 0.115, y: CGFloat(original.height) * 0.57,
                            width: CGFloat(original.width) * 0.77, height: CGFloat(original.height) * 0.173).integral
        guard let cropped = original.cropping(to: bounds) else { return nil }
        // Preserve the original high-resolution pixels. White becomes transparent
        // during native image rendering; no screen-resolution lockFocus conversion.
        let width = cropped.width, height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let white = min(pixels[index], pixels[index + 1], pixels[index + 2])
            pixels[index] -= white; pixels[index + 1] -= white; pixels[index + 2] -= white
            pixels[index + 3] = 255 - white
            if pixels[index + 3] < 12 {
                pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0; pixels[index + 3] = 0
            }
        }
        // The context references pixels; materialize the processed buffer explicitly.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }()
    var body: some View {
        Group {
            if let image = Self.image {
                VStack(spacing: 1) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 150, height: 29)
                    Text("MUSIC LIBRARIAN")
                        .font(.system(size: 7.5, weight: .medium))
                        .tracking(2.3)
                        .foregroundStyle(.primary)
                        .fixedSize()
                    }
                    .accessibilityLabel("TagCraft Music Librarian")
            } else {
                Text("TagCraft").font(.headline)
            }
        }.frame(width: 154, height: 54, alignment: .center)
    }
}
struct ContentView: View {
    @EnvironmentObject var m: Model
    @AppStorage("inspectorWidth", store: AppPreferences.defaults) private var inspectorWidth = 405.0
    @State private var inspectorDragStart: Double?
    @AppStorage("showInspector", store: AppPreferences.defaults) private var showInspector = true
    @FocusState private var filterFocused: Bool
    @State private var showMaskBuilder = false
    @State private var maskDraft = ""
    @State private var insertField = "Artist"
    var selectionHeaderIcon: String {
        let visible = Set(m.filtered.map(\.url))
        return !visible.isEmpty && visible.isSubset(of: m.selection) ? "checkmark.square.fill" : "square"
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(m.folder?.lastPathComponent ?? "Your TagCraft workspace").font(.title2.bold())
                                if let folder = m.folder {
                                    Text(folder.path).font(.callout).foregroundStyle(.secondary)
                                        .textSelection(.enabled).lineLimit(2).help(folder.path)
                                }
                            }
                            Text("\(m.tracks.count) tracks · " + m.selectionSummary).foregroundStyle(m.hiddenSelection.isEmpty ? Color.secondary : Color.primary).font(.callout)
                            if !m.hiddenSelection.isEmpty {
                                Button("Clear Hidden Selection") { m.requestSelection(m.selection.subtracting(m.hiddenSelection)) }.buttonStyle(.link).disabled(m.busy)
                            }
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Filter workspace", text: $m.query)
                                .textFieldStyle(.plain).focused($filterFocused)
                                .help("Filter by artist, title, album or filename")
                            if !m.query.isEmpty {
                                Button { m.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                    .buttonStyle(.plain).help("Clear filter").accessibilityLabel("Clear workspace filter")
                            }
                        }.padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                            .frame(minWidth: 150, idealWidth: 240, maxWidth: 280)
                    }.padding()
                    if let folder = m.folder {
                        ScrollView(.horizontal) {
                            HStack(spacing: 5) {
                                ForEach(FolderMonitor.ancestors(folder), id: \.path) { ancestor in
                                    Button(ancestor.lastPathComponent.isEmpty ? "/" : ancestor.lastPathComponent) { m.openFolder(ancestor) }.buttonStyle(.link)
                                    Text("›").foregroundStyle(.secondary)
                                }
                            }.font(.caption).padding(.horizontal)
                        }.frame(height: 24)
                    }
                    HStack(spacing: 12) {
                        Toggle("Include subfolders", isOn: $m.includeSubfolders)
                            .toggleStyle(.checkbox)
                            .help("Include MP3 files in every subfolder, including the library if it is inside this folder")
                            .onChange(of: m.includeSubfolders) { _, _ in m.scan() }
                        Button("Select All Visible") { m.requestSelection(m.selection.union(m.filtered.map(\.url))) }
                            .help("Select every track matching the current filter")
                        Button("Select None") { m.requestSelection([]) }
                            .help("Clear the track selection")
                        Menu("Columns") {
                            Button("Customize Columns…") { m.showColumnSettings = true }
                            Button("Auto Fit Columns") { m.autoFitColumns() }
                        }.fixedSize()
                        Text("Use checkboxes, Shift-click for a range, or Command-click for individual tracks.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }.padding(.horizontal).padding(.bottom, 10)
                    Table(m.filtered, selection: Binding(get: { m.selection }, set: { m.requestSelection($0) }), sortOrder: $m.sortOrder) {
                        TableColumn("✓") { (track: Track) in
                            Toggle("Select \(track.filename)", isOn: Binding(
                                get: { m.selection.contains(track.url) },
                                set: { checked in
                                    var next = m.selection
                                    if checked { next.insert(track.url) } else { next.remove(track.url) }
                                    m.requestSelection(next)
                                }
                            )).toggleStyle(.checkbox).labelsHidden()
                                .help("Select or deselect \(track.filename)")
                        }.width(30)
                        workspaceColumnGroup0
                        workspaceColumnGroup1
                        workspaceColumnGroup2

                    }
                    .overlay {
                        if m.folder == nil {
                            VStack(spacing: 18) {
                                StatisticsBrandLogo(width: 224).padding(26)
                                Text("Your TagCraft workspace").font(.title2.bold())
                                Text("Open a folder to prepare filenames, edit tags and organize your music.")
                                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Open Workspace…") { m.pick() }.buttonStyle(.borderedProminent)
                            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                        }
                    }
                    .onChange(of: m.selection) { _, _ in m.loadSelection() }
                    .contextMenu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(m.selected.map(\.url)) }
                        Button("Edit Tags in Selected Files…") { m.beginBatch() }.disabled(m.selection.isEmpty || m.dirty)
                        Button("Select All Visible Tracks") { m.requestSelection(Set(m.filtered.map(\.url))) }
                        Button("Play") { m.play() }.disabled(m.selection.isEmpty)
                    }
                    Divider()
                    MiniPlayer(playback: m.playback)
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: m.failures.isEmpty ? "info.circle" : "exclamationmark.triangle")
                        Text(m.message.isEmpty ? "Select tracks to edit tags or move them into your library." : m.message)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            .help(m.message)
                        if !m.failures.isEmpty && !m.busy {
                            Button("Details…") { m.showJobErrors = true }
                            Button("Retry Failed") { m.runPlans(m.failures, label: "Retry") }
                        }
                        Spacer(minLength: 12)
                        if m.busy {
                            if m.progressTotal > 0 {
                                ProgressView(value: Double(m.progressDone), total: Double(m.progressTotal)).frame(width: 75)
                            } else { ProgressView().controlSize(.small) }
                            Text(m.progressText).lineLimit(1).truncationMode(.middle)
                                .frame(maxWidth: 260, alignment: .trailing).help(m.progressText)
                            Button("Cancel") { m.cancellation.cancel() }
                                .help("Cancel remaining work; a file already being written or moved finishes first")
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
                        .accessibilityElement(children: .contain).accessibilityLabel("Workspace status")
                }
                if showInspector {
                Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 10)
                    .overlay { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 1) }
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture().onChanged { value in
                        if inspectorDragStart == nil { inspectorDragStart = inspectorWidth }
                        inspectorWidth = min(700, max(300, (inspectorDragStart ?? 405) - value.translation.width))
                    }.onEnded { _ in inspectorDragStart = nil })
                    .accessibilityLabel("Tag Inspector width")
                    .accessibilityValue("\(Int(min(inspectorWidth, max(300, geometry.size.width * 0.4)))) points")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: inspectorWidth = min(700, inspectorWidth + 40)
                        case .decrement: inspectorWidth = max(300, inspectorWidth - 40)
                        @unknown default: break
                        }
                    }
                    .contextMenu {
                        Button("Narrower Inspector") { inspectorWidth = max(300, inspectorWidth - 40) }
                        Button("Wider Inspector") { inspectorWidth = min(700, inspectorWidth + 40) }
                        Button("Hide Inspector") { showInspector = false }
                    }
                    .help("Drag left or right to resize the Tag Inspector")
                inspector.frame(width: min(inspectorWidth, max(300, geometry.size.width * 0.4))).disabled(m.busy)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { actionBar }

        }
        }
        .task { m.restoreMusicFolder(); m.restoreStatistics() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first, !m.busy else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    m.openFolder(isDirectory ? url : url.deletingLastPathComponent())
                }
            }
            return true
        }
        .background(ToolbarDefaults(model: m, toggleAll: {
            let visible = Set(m.filtered.map(\.url))
            m.requestSelection(visible.isSubset(of: m.selection) ? m.selection.subtracting(visible) : m.selection.union(visible))
        }, allSelected: selectionHeaderIcon == "checkmark.square.fill"))
        .sheet(isPresented: Binding(get: { m.showQuality && !m.showStatistics }, set: { m.showQuality = $0 })) { QualityReviewView().environmentObject(m) }
        .sheet(isPresented: $m.showJobErrors) { JobErrorsView().environmentObject(m) }
        .sheet(isPresented: Binding(get: { m.showCleanSettings && !m.showMoves }, set: { m.showCleanSettings = $0 })) { CleanSettingsView().environmentObject(m) }
        .sheet(isPresented: $m.showMagicReview) { MagicReviewView().environmentObject(m) }
        .sheet(isPresented: $m.showWorkflow) { WorkflowView().environmentObject(m) }
        .sheet(isPresented: $m.showStatistics) { StatisticsView().environmentObject(m) }
        .sheet(isPresented: $m.showTechnical) { TechnicalView().environmentObject(m) }
        .sheet(isPresented: $m.showReadTerms) { LicenseTermsView(required: false, accept: {}, close: { m.showReadTerms = false }, decline: {}) }
        .sheet(isPresented: $m.showUpdateCheck) { UpdateCheckView() }
        .sheet(isPresented: $m.showAbout) { AboutTagCraftView() }
        .sheet(isPresented: $m.showLibraryStructure) { LibraryStructureView().environmentObject(m) }
        .sheet(isPresented: $m.showInspectorDisplaySettings) { InspectorDisplaySettings().environmentObject(m) }
        .sheet(isPresented: $m.showColumnSettings) { WorkspaceColumnSettings().environmentObject(m) }
        .sheet(isPresented: $m.showPurgeSettings) { PurgeSettingsView().environmentObject(m) }
        .sheet(isPresented: $m.showBatch) { batchEditor }
        .sheet(isPresented: $m.showMoves) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(m.operation == "Preparation Workflow" ? m.workflow.name : m.operation).font(.title2.bold())
                    Text(m.selectionSummary).font(.callout)
                    if m.operation == "Move to Library", let library = m.library {
                        Text(library.path).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                if m.operation == "Duplicate Check" { Text(m.duplicateSummary).font(.caption).foregroundStyle(.secondary) }
                if m.operation == "Move to Library" || (m.operation == "Preparation Workflow" && m.workflow.move) {
                    Text(m.libraryStructure.summary)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if m.operation == "Move to Library" {
                    Picker("Placement", selection: $m.movePlacement) {
                        ForEach(LibraryPlacement.allCases) { Text($0.label).tag($0) }
                    }.onChange(of: m.movePlacement) { _, _ in m.previewMove() }
                    Text("Applies to this move only. Artist folders follow Settings. Album placement uses individual-track placement when the album tag is empty.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if m.operation == "Purge Tags" {
                    Text("Remove the listed tag content from selected files. Other frames and audio are preserved. Full backups are saved in .TagCraft Backups beside each file. Restore a backup to undo a purge. Corresponding legacy ID3v1 fields are also cleared.").foregroundStyle(.secondary)
                }
                Text(m.operation == "Duplicate Check" ? "Matching compressed audio payloads, ignoring ID3 tags. Different encodings of the same recording are not detected. This report is read-only." : m.operation == "Purge Tags" ? "Review the fields to delete below." : m.operation == "Clean Filenames" ? "Prepare the raw filename without reading or changing tags or reordering fields. Apply your configured Clean rules; changed characters are highlighted below. Open Clean Rules to choose punctuation, spacing, capitalization and removable labels. Conflicts are skipped." : (m.operation == "Get Tags from Filename" ? "Choose a layout or build a custom mask. Only fields in the mask are replaced. Other tags are preserved; backups are created. Separators must match exactly. The mask is applied literally, including parentheses. Yellow rows need review for repeated separators or unmatched brackets; they are still included when you apply." : (isRenaming ? "Build filenames from saved tags. Choose a preset or custom mask and review current and proposed names. Missing tags and conflicts are skipped. Files stay in their current folders; tags are unchanged." : "Review the destinations. Files with conflicts or missing artists will be skipped."))).foregroundStyle(.secondary)
                if isMagic {
                    HStack {
                        Picker("Input Layout", selection: $m.extractionLayout) {
                            ForEach(FilenameMask.presets, id: \.self) { Text($0) }
                        }.frame(width: 350)
                        Button("Build Input Mask…") { maskDraft = m.extractionMask; showMaskBuilder = true }
                    }.disabled(m.busy)
                    Text("Clean → Extract using \(m.extractionMask) → Rename as Artist - Title.mp3. Tags and final filenames are applied only after review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if m.operation == "Get Tags from Filename" || isRenaming {
                    HStack {
                        Picker("Filename Layout", selection: layoutBinding) {
                            ForEach(FilenameMask.presets, id: \.self) { Text($0) }
                        }.frame(maxWidth: 360)
                        Button("Build Custom Mask…") {
                            maskDraft = activeMask
                            if isRenaming && insertField == "Skip" { insertField = "Artist" }
                            showMaskBuilder = true
                        }
                    }
                    if !isRenaming { delimiterOptions }
                    Text(activeMask + "  (extension excluded)").font(.caption.monospaced()).textSelection(.enabled)
                }
                HStack {
                    Button("Include All") { m.excluded = [] }
                    Button("Exclude All") { m.excluded = Set(m.moves.map(\.source)) }
                    if m.operation == "Clean Filenames" { Button("Clean Rules…") { m.showCleanSettings = true } }
                    if m.operation == "Move to Library" || (m.operation == "Preparation Workflow" && m.workflow.move) {
                        Button("Check Against Library for Duplicates") { m.checkDuplicates() }.disabled(m.busy)
                    }
                    Spacer()
                    Text("\(m.eligibleMoves.count) files included").font(.caption)
                }
                if m.busy {
                    HStack { ProgressView().controlSize(.small); Text(m.progressText).font(.caption); Button("Cancel Check") { m.cancellation.cancel() } }
                }
                List(m.moves) { item in
                    HStack(alignment: .top) {
                    Toggle("Include file", isOn: Binding(get: { !m.excluded.contains(item.source) }, set: { checked in
                        if checked { m.excluded.remove(item.source) } else { m.excluded.insert(item.source) }
                    })).labelsHidden().disabled(item.issue != nil)
                    VStack(alignment: .leading, spacing: 4) {
                        if m.operation == "Clean Filenames" || isRenaming || m.operation == "Preparation Workflow" {
                            Text("CURRENT FILENAME").font(.caption2).foregroundStyle(.secondary)
                            FilenameDiffText(before: item.source.lastPathComponent, after: item.destination?.lastPathComponent ?? item.source.lastPathComponent, proposed: false)
                            Label("NEW FILENAME", systemImage: "arrow.down").font(.caption2).foregroundStyle(.secondary)
                            FilenameDiffText(before: item.source.lastPathComponent, after: item.destination?.lastPathComponent ?? item.source.lastPathComponent, proposed: true)
                            if let issue = item.issue {
                                Text((issue == "Already clean." || issue == "Already named correctly." || issue == "No change needed.") ? "No change needed" : "Skipped: " + issue)
                                    .font(.caption).foregroundStyle((issue == "Already clean." || issue == "Already named correctly." || issue == "No change needed.") ? Color.secondary : Color.orange)
                            } else {
                                Text(item.statusText ?? "Will rename").font(.caption).foregroundStyle(.green)
                            }
                        } else {
                            Text(item.source.lastPathComponent).bold()
                            Text(m.previewDescription(item)).font(.caption).foregroundStyle(item.issue == nil ? Color.secondary : Color.orange).textSelection(.enabled)
                        }
                        if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        if m.operation == "Move to Library", let track = m.tracks.first(where: { $0.url == item.source }) {
                            let suggestions = m.artistSuggestions[item.source] ?? []
                            if !suggestions.isEmpty {
                                Picker("Artist folder", selection: Binding(get: { m.artistChoices[item.source] ?? track.tags.artist }, set: { value in
                                    m.artistChoices[item.source] = value; m.previewMove()
                                })) {
                                    Text(track.tags.artist + " (original)").tag(track.tags.artist)
                                    ForEach(suggestions, id: \.self) { Text($0).tag($0) }
                                }
                                Text("Suggested existing artist folders; tags change only through tag editing.").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let warning = item.warning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.primary)
                        }
                    }.padding(.vertical, 4)
                    }.disabled(m.busy)
                    .listRowBackground(item.warning == nil ? Color.clear : Color.yellow.opacity(0.22))
                }
                HStack { Spacer(); Button("Cancel") { m.showMoves = false }; Button("\(m.operation == "Purge Tags" ? "Purge" : "Apply to") \(m.eligibleMoves.count) Files") { m.applyPreview() }.buttonStyle(.borderedProminent).tint(m.operation == "Purge Tags" ? .red : .accentColor).disabled(m.eligibleMoves.isEmpty || m.busy) }
            }.padding(24).frame(minWidth: 800, idealWidth: 800, maxWidth: .infinity, minHeight: 480, idealHeight: 550, maxHeight: .infinity).background(ResizableReviewSheet())
                .onAppear {
                    m.excluded = []
                    m.previewFingerprints = Dictionary(uniqueKeysWithValues: m.moves.map { ($0.source, FileJobs.fingerprint($0.source)) })
                }
                .onChange(of: m.cleanRules) { _, _ in if m.operation == "Clean Filenames" { m.previewClean() } }
                .onChange(of: m.extractionLayout) { _, _ in
                    if m.operation == "Get Tags from Filename" { m.previewExtract() }
                    else if isMagic { m.workflow.extractionMask = m.extractionMask; m.previewWorkflow() }
                }
                .onChange(of: m.renameLayout) { _, _ in if isRenaming { m.previewRename() } }
                .onChange(of: m.renameCustomMask) { _, _ in if isRenaming { m.previewRename() } }
                .onChange(of: m.ignoredGroups) { _, _ in if m.operation == "Get Tags from Filename" { m.previewExtract() } }
                .onChange(of: m.customMask) { _, _ in
                    if m.operation == "Get Tags from Filename" { m.previewExtract() }
                    else if isMagic { m.workflow.extractionMask = m.extractionMask; m.previewWorkflow() }
                }
                .sheet(isPresented: $showMaskBuilder) { maskBuilder }
                .sheet(isPresented: Binding(get: { m.showCleanSettings && m.showMoves }, set: { m.showCleanSettings = $0 })) { CleanSettingsView().environmentObject(m) }
        }
    }
    var actionBarDisplayPicker: some View {
        Picker("Action Bar Display", selection: $m.showActionText) {
            Text("Icons and Text").tag(true)
            Text("Icons Only").tag(false)
        }.pickerStyle(.inline)
    }
    @ViewBuilder func barItem(_ index: Int) -> some View {
        switch index {
        case 0:
            Menu {
                Button("Library Statistics…") { m.showStatistics = true }
                Button("Check Workspace Tag Quality…") { m.checkTagQuality() }.disabled(m.tracks.isEmpty || m.busy)
                Button("Export Last Duplicate Report…") { m.exportDuplicateReport() }.disabled(m.duplicateResults.isEmpty)
                Button("Check Library Duplicates…") { m.checkDuplicates() }.disabled(m.library == nil)
            } label: { Label("Library Tools", systemImage: "books.vertical") }
        case 1:
            Menu {
                Button("Open Workspace Folder…") { m.pick() }
                Divider()
                ForEach(m.recentFolders, id: \.self) { path in Button(path) { m.openFolder(URL(fileURLWithPath: path)) } }
                Button("Clear Recent Workspaces") { m.clearRecentWorkspaces() }.disabled(m.recentFolders.isEmpty)
            } label: { Label("Open Workspace", systemImage: "folder") }
        case 2: Button { m.scan() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(m.folder == nil)
        case 5: Button { m.undoMove() } label: { Label(m.fileUndoManager?.undoMenuItemTitle ?? "Undo", systemImage: "arrow.uturn.backward") }.disabled(m.fileUndoManager?.canUndo != true)
        case 6: Button { m.beginBatch() } label: { Label { Text("Edit ALL Tags") } icon: { EditSelectedTagsIcon() } }.help("Edit all supported tags in the selected files, including tags hidden from Tag Inspector.").disabled(m.selection.isEmpty || m.dirty)
        case 7: Button { m.previewClean() } label: { Label { Text("Clean") } icon: { BroomIcon() } }.disabled(m.selection.isEmpty || m.dirty)
        case 8: Button { m.beginMagic() } label: { Label("Magic", systemImage: "wand.and.stars") }.disabled(m.selection.isEmpty || m.dirty)
        case 9: Button { m.previewPurge() } label: { Label("Purge", systemImage: "eraser") }.disabled(m.selection.isEmpty || m.dirty)
        case 10: Button { m.previewRename() } label: { Label { Text("Rename from Tags") } icon: { RenameFromTagsIcon() } }.disabled(m.selection.isEmpty || m.dirty)
        case 11: Button { m.previewExtract() } label: { Label { Text("Get Tags from Filename") } icon: { FilenameToTagsIcon() } }.disabled(m.selection.isEmpty || m.dirty)
        case 12:
            Button { m.prepareMovePreview() } label: { Label("Move to Library", systemImage: "tray.and.arrow.down") }.disabled(m.selection.isEmpty || m.dirty)
        case 13: Button { m.showWorkflow = true } label: { Label("Workflow", systemImage: "list.bullet.clipboard") }
        default:
            Menu {
                Button("Library Structure…") { m.showLibraryStructure = true }
                Button("Clean Rules…") { m.showCleanSettings = true }
                Button("Preparation Workflows…") { m.showWorkflow = true }
                Button("Tags to Purge…") { m.showPurgeSettings = true }
                Button("Tags to Display in Tag Inspector…") { m.showInspectorDisplaySettings = true }
                Button("Customize Columns…") { m.showColumnSettings = true }
                        Button("Auto Fit Columns") { m.autoFitColumns() }
                Divider()
                Button(m.library == nil ? "Choose Library…" : "Change Library…") { m.pick(library: true) }
                Divider()
                Toggle("Automatic Refresh", isOn: $m.autoRefresh).onChange(of: m.autoRefresh) { _, _ in m.configureMonitor() }
                Menu("Action Bar Display") { actionBarDisplayPicker; Toggle("Compact Toolbar", isOn: $compactToolbar) }
                Toggle("Show Tag Inspector", isOn: $showInspector)
                Divider()
                Button("Check for Updates…") { m.showUpdateCheck = true }
                Button("License & Usage Notice…") { m.showReadTerms = true }
                Button("About TagCraft…") { m.showAbout = true }
            } label: { Label("Settings", systemImage: "gearshape") }
        }
    }
    @AppStorage("compactToolbar", store: AppPreferences.defaults) private var compactToolbar = true
    var actionOrder: [Int] { compactToolbar ? [1, 2, 5, 8, 6, 12, 0, 15, 7, 9, 11, 10, 13] : [1, 2, 5, 8, 7, 9, 11, 6, 10, 12, 0, 13, 15] }
    func fittedBar(_ count: Int) -> some View {
        HStack(spacing: 12) {
            Link(destination: AppRelease.website) {
                BrandWordmark().padding(.top, 6)
            }.buttonStyle(.plain).help("Open TagCraft on GitHub")
                .accessibilityLabel("TagCraft on GitHub")
            ForEach(Array(actionOrder.prefix(count)), id: \.self) { index in
                if index == 8 || index == 12 { Divider().frame(height: 36).accessibilityHidden(true) }
                barItem(index).accessibilityLabel(actionNames[index]).quickHint(barHints[index])
            }
            if count < actionOrder.count {
                Menu {
                    ForEach(Array(actionOrder.dropFirst(count)), id: \.self) { index in barItem(index) }
                } label: { Label("More", systemImage: "chevron.right.2") }
                .menuIndicator(.hidden).help("Show hidden actions")
            }
        }.labelStyle(ActionBarLabel(showText: m.showActionText))
            .buttonStyle(.plain).disabled(m.busy).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8).padding(.vertical, 10)
    }
    var actionNames: [String] { ["Library Tools", "Open Workspace", "Refresh Workspace", "Play", "Stop", "Undo", "Edit ALL Tags", "Clean Filenames", "Magic", "Purge Tags", "Rename from Tags", "Get Tags from Filename", "Move to Library", "Preparation Workflows", "Filter Tracks", "Settings"] }
    var barHints: [String] {
        ["Library tools\n" + (m.library?.path ?? "No library selected"), "Open a workspace or recent workspace", "Refresh workspace", "Play selected track", "Stop playback", "Undo last file action", "Edit all supported tags in selected files, including tags hidden from Tag Inspector", "Prepare raw filenames; does not read or change tags", "Intelligently cleans filenames, extracts tags and renames files in one reviewed plan", "Purge configured tags", "Build filenames from saved tags", "Extract tags from filenames", "Move to library\n" + (m.library?.path ?? "No library selected"), "Preparation workflows", "Filter tracks", "Settings"]
    }
    var actionBar: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    fittedBar(actionOrder.count)
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        BrandWaveform().frame(width: 120, height: 48)
                        Text(AppRelease.fullLabel).font(.callout).foregroundStyle(.secondary)
                    }.fixedSize().padding(.trailing, 16)
                }
                fittedBar(actionOrder.count)
                fittedBar(12); fittedBar(11); fittedBar(10); fittedBar(9)
                fittedBar(8); fittedBar(7); fittedBar(6); fittedBar(5)
                fittedBar(4); fittedBar(3); fittedBar(2); fittedBar(1); fittedBar(0)
            }.frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .contextMenu { actionBarDisplayPicker; Toggle("Compact Toolbar", isOn: $compactToolbar); Toggle("Show Tag Inspector", isOn: $showInspector) }
            Divider()
        }.background(.bar).zIndex(100)
    }

    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    var workspaceColumnGroup0: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Filename", value: \.filename) { track in PlayingFilename(track: track, playback: m.playback) }.width(min: 100, ideal: 240, max: 1200)
        TableColumn("Artist", value: \.artist).width(min: 60, ideal: 140, max: 900)
        TableColumn("Title", value: \.title).width(min: 60, ideal: 160, max: 900)
        TableColumn("Album", value: \.album).width(min: 60, ideal: 140, max: 900)
        TableColumn("Track", value: \.trackNumber).width(min: 45, ideal: 60, max: 300)
        TableColumn("Year", value: \.year).width(min: 45, ideal: 60, max: 300)
        TableColumn("Status", value: \.status) { Text($0.issue == nil ? "Ready" : "Read only").foregroundStyle($0.issue == nil ? Color.secondary : Color.orange).help($0.issue ?? "") }.width(min: 60, ideal: 80, max: 500)
        TableColumn("Album Artist", value: \.albumArtistColumn) { track in Text(track.tags.value("Album Artist").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Album Artist") }.width(min: 60, ideal: 140, max: 900)
    }
    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    var workspaceColumnGroup1: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Disc", value: \.discColumn) { track in Text(track.tags.value("Disc").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Disc") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Composer", value: \.composerColumn) { track in Text(track.tags.value("Composer").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Composer") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Conductor", value: \.conductorColumn) { track in Text(track.tags.value("Conductor").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Conductor") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("BPM", value: \.bpmColumn) { track in Text(track.tags.value("BPM").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("BPM") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Publisher", value: \.publisherColumn) { track in Text(track.tags.value("Publisher").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Publisher") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Copyright", value: \.copyrightColumn) { track in Text(track.tags.value("Copyright").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Copyright") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Encoded By", value: \.encodedByColumn) { track in Text(track.tags.value("Encoded By").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Encoded By") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Language", value: \.languageColumn) { track in Text(track.tags.value("Language").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Language") }.width(min: 60, ideal: 140, max: 900)
    }
    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    var workspaceColumnGroup2: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Grouping", value: \.groupingColumn) { track in Text(track.tags.value("Grouping").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Grouping") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Subtitle", value: \.subtitleColumn) { track in Text(track.tags.value("Subtitle").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Subtitle") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("ISRC", value: \.isrcColumn) { track in Text(track.tags.value("ISRC").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("ISRC") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Lyricist", value: \.lyricistColumn) { track in Text(track.tags.value("Lyricist").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Lyricist") }.width(min: 60, ideal: 140, max: 900)
        TableColumn("Lyrics", value: \.lyricsColumn) { track in Text(track.tags.value("Lyrics").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Open the Tag Inspector to read or edit embedded lyrics.") }.width(min: 80, ideal: 220, max: 900)
        TableColumn("Genre", value: \.genreColumn) { track in Text(track.tags.value("Genre").replacingOccurrences(of: "\n", with: " · ")).lineLimit(1).help("Genre") }.width(min: 60, ideal: 140, max: 900)
    }

    var delimiterOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ignore delimiters inside:").font(.caption)
                Toggle("( )", isOn: $m.ignoreParentheses)
                Toggle("{ }", isOn: $m.ignoreBraces)
                Toggle("[ ]", isOn: $m.ignoreBrackets)
            }.toggleStyle(.checkbox)
            Text("Applies to matching pairs, including nested groups. Brackets written explicitly in the mask still act as delimiters.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    var isMagic: Bool { m.operation == "Preparation Workflow" && m.workflow.name == "Magic — Clean, Extract & Rename" }
    var isRenaming: Bool { m.operation == "Rename Files from Tags" }
    var activeMask: String { isRenaming ? m.renameMask : m.extractionMask }
    var layoutBinding: Binding<String> {
        Binding(get: { isRenaming ? m.renameLayout : m.extractionLayout }, set: {
            if isRenaming { m.renameLayout = $0 } else { m.extractionLayout = $0 }
        })
    }
    var maskError: String? {
        do {
            if isRenaming { _ = try FilenameTemplate(maskDraft) } else { _ = try FilenameMask(maskDraft, ignoredGroups: m.ignoredGroups) }
            return nil
        }
        catch { return error.localizedDescription }
    }
    var maskBuilder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isRenaming ? "Build Rename Mask" : "Build Custom Filename Mask").font(.title2.bold())
            Text(isRenaming ? "Insert tag variables and type separators or literal text to build filenames. Leave out .mp3; it is added automatically. Files stay in their current folders." : "Insert variables and type the exact separators or literal text used in filenames. Leave out .mp3. Use Skip for text that should not become a tag.").foregroundStyle(.secondary)
            TextField("Example: {Track} - {Artist} - {Title}", text: $maskDraft).textFieldStyle(.roundedBorder).font(.body.monospaced())
            HStack {
                Picker("Variable", selection: $insertField) {
                    ForEach(FilenameMask.fields.filter { !isRenaming || $0 != "Skip" }, id: \.self) { Text($0) }
                }.frame(width: 250)
                Button("Append Variable") { maskDraft += "{" + insertField + "}" }
                Button("Append Separator") { maskDraft += " - " }
            }
            Text("Examples: {Artist} - {Album} - {Track} - {Title}   •   {Title} ({Year}) - {Artist}").font(.caption).textSelection(.enabled)
            if let error = maskError { Text(error).foregroundStyle(.orange).font(.caption) }
            if !isRenaming { delimiterOptions }
            Text("Preview").font(.headline)
            List(m.selected.prefix(5)) { track in
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.filename).bold()
                    Text(maskSample(track)).font(.caption).textSelection(.enabled)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { showMaskBuilder = false }
                Button("Use Mask") {
                    if isMagic {
                        m.customMask = maskDraft
                        m.extractionLayout = "Custom Mask"
                        m.workflow.extractionMask = maskDraft
                        m.previewWorkflow()
                    } else if isRenaming {
                        m.renameCustomMask = maskDraft
                        m.renameLayout = "Custom Mask"
                        m.previewRename()
                    } else {
                        m.customMask = maskDraft
                        m.extractionLayout = "Custom Mask"
                        m.previewExtract()
                    }
                    showMaskBuilder = false
                }.buttonStyle(.borderedProminent).disabled(maskError != nil)
            }
        }.padding(24).frame(minWidth: 760, idealWidth: 760, maxWidth: .infinity, minHeight: 480, idealHeight: 490, maxHeight: .infinity).background(ResizableReviewSheet())
    }
    func maskSample(_ track: Track) -> String {
        do {
            if isRenaming { return "New filename: " + (try FilenameTemplate(maskDraft).filename(tags: track.tags)) }
            let mask = try FilenameMask(maskDraft, ignoredGroups: m.ignoredGroups)
            let filename = isMagic ? (try m.workflow.cleanRules.clean(track.filename, tags: Tags()).0) : track.filename
            let tags = try mask.extract(filename, existing: track.tags)
            var parts = mask.captures.filter { $0 != "Skip" }.map { "\($0): \(tags.value($0))" }
            let review = mask.review(track.filename)
            parts += review.ignored.map { "Ignored: \($0)" }
            if let warning = review.warning { parts.append("⚠ " + warning) }
            return parts.joined(separator: " • ")
        } catch { return error.localizedDescription }
    }
    func tagField(_ name: String, batch: Bool) -> some View {
        let mixed = (batch ? m.batchMixed : m.inspectorMixed).contains(name)
        let cleared = (batch ? m.batchCleared : m.inspectorCleared).contains(name)
        let value = Binding<String>(get: { (batch ? m.batchDraft : m.draft).value(name) }, set: { m.editTagField(name, value: $0, batch: batch) })
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(name, isOn: Binding(get: { (batch ? m.batchFields : m.inspectorFields).contains(name) }, set: { m.checkTagField(name, enabled: $0, batch: batch) }))
                    .toggleStyle(.checkbox).frame(width: batch ? 120 : 90, alignment: .leading)
                if name != "Lyrics" {
                    TextField("", text: value, prompt: Text(cleared ? "Will remove" : mixed ? "Multiple values" : ""))
                        .textFieldStyle(.roundedBorder).accessibilityLabel(name + (mixed ? ", multiple values" : ""))
                }
                if cleared { Text("Remove").font(.caption.bold()).foregroundStyle(.red) }
            }
            if name == "Lyrics" {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: value).font(.body).frame(minHeight: 140).accessibilityLabel("Lyrics")
                    if value.wrappedValue.isEmpty { Text(cleared ? "Will remove lyrics" : mixed ? "Multiple values" : "Lyrics").foregroundStyle(.secondary).padding(5).allowsHitTesting(false) }
                }.overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.4)))
            }
        }
    }
    func batchField(_ name: String, _ value: Binding<String>) -> some View { tagField(name, batch: true) }
    var batchEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit ALL Tags in Selected Files").font(.title2.bold())
            Text(m.selectionSummary).font(.callout)
            Text("Check the tracks and fields to update. Editing a value checks its field automatically. Untouched empty inputs are skipped. Erasing content or using Clear Selected marks tags for removal. Other fields are preserved. Full file backups are created.").font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading) {
                    HStack {
                        Button("Select All") { m.batchTargets = Set(m.batchCandidates.map(\.url)) }
                        Button("Select None") { m.batchTargets = [] }
                    }
                    ArtworkThumbnail(summary: m.batchArtwork).onDrop(of: [.fileURL], isTargeted: nil) { m.acceptArtworkDrop($0, batch: true) }
                    Toggle("Apply artwork to checked files", isOn: $m.batchApplyArtwork)
                    ArtworkOptions().environmentObject(m)
                    HStack {
                        Button("Choose Image…") { m.chooseBatchArtwork() }
                        Button("Remove Artwork") { m.batchApplyArtwork = true; m.batchRemoveArtwork = true; m.batchArtworkData = nil }
                    }
                    if let data = m.batchArtworkData, let image = NSImage(data: data) {
                        HStack { Image(nsImage: image).resizable().scaledToFit().frame(width: 52, height: 52); Text("New image — applied with Apply Tags").font(.caption) }
                    }
                    if m.batchApplyArtwork && m.batchRemoveArtwork { Text("Artwork will be removed from checked files.").font(.caption).foregroundStyle(.orange) }
                    List(m.batchCandidates) { track in
                        Toggle(track.filename, isOn: Binding(get: { m.batchTargets.contains(track.url) }, set: { enabled in
                            if enabled { m.batchTargets.insert(track.url) } else { m.batchTargets.remove(track.url) }
                        })).help(track.url.path)
                    }
                }.frame(width: 310)
                ScrollView { VStack(spacing: 12) {
                    HStack {
                        Button("Common Fields") { m.batchFields = Set(["Title", "Artist", "Album", "Album Artist", "Year", "Genre", "Track"] + Tags.extraFields.map(\.label)).subtracting(m.batchMixed) }
                        Button("No Fields") { m.batchFields = []; m.batchCleared = [] }
                        Button("Clear Selected") { m.clearCheckedTags(batch: true) }.disabled(m.batchFields.isEmpty)
                        Spacer()
                    }
                    batchField("Title", $m.batchDraft.title)
                    batchField("Artist", $m.batchDraft.artist)
                    batchField("Album", $m.batchDraft.album)
                    batchField("Album Artist", $m.batchDraft.albumArtist)
                    batchField("Year", $m.batchDraft.year)
                    batchField("Genre", $m.batchDraft.genre)
                    batchField("Track", $m.batchDraft.track)
                    ForEach(Tags.extraFields, id: \.id) { field in
                        batchField(field.label, Binding(get: { m.batchDraft.extra[field.id] ?? "" }, set: { m.batchDraft.extra[field.id] = $0.isEmpty ? nil : $0 }))
                    }
                    Text("Common values are shown for checked tracks; differing fields show Multiple values. Untouched empty inputs never remove tags; erasing content marks a checked removal. Clear Selected marks checked fields for removal, confirmed before applying. Common Fields checks only fields shared by checked tracks; artwork is retained unless explicitly updated; other ID3 frames are retained.").font(.caption).foregroundStyle(.secondary)
                } }
            }
            HStack {
                Text("\(m.batchTargets.count) tracks\n" + m.batchPatch.summary).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { m.showBatch = false }
                Button("Apply Tags") { m.applyBatch() }.buttonStyle(.borderedProminent).disabled(m.batchTargets.isEmpty || (m.batchPatch.effective.isEmpty && !(m.batchApplyArtwork && (m.batchArtworkData != nil || m.batchRemoveArtwork))))
            }
        }.padding(24).frame(minWidth: 900, idealWidth: 900, maxWidth: .infinity, minHeight: 480, idealHeight: 650, maxHeight: .infinity).background(ResizableReviewSheet())
            .onChange(of: m.batchTargets) { _, _ in m.refreshBatchArtwork(); m.refreshBatchValues() }
    }
    var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Tag Inspector", systemImage: "tag").font(.headline)
                Spacer()
                Button("Artwork & Details…") { m.loadTechnical() }.disabled(m.selection.count != 1 || m.busy)
            }
            if m.selection.isEmpty {
                VStack(spacing: 16) {
                    BrandWaveform().frame(width: 140, height: 60).opacity(0.65)
                    Text("Select a track").font(.title2.bold()).foregroundStyle(.secondary)
                    Text("Edit individual tracks or select several for batch changes.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ArtworkThumbnail(summary: m.inspectorArtwork)
                Text(m.selection.count == 1 ? m.selected.first?.filename ?? "" : "\(m.selection.count) tracks selected").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if m.selection.count > 1 { Text("Only shared values are shown. Multiple values means tags differ. Editing checks a field; empty inputs preserve existing tags.").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Menu("Tags") {
                        Button("Select All Tags") { m.inspectorTracksIntent = true; m.inspectorFields = m.inspectorDisplayedFields }
                        Button("Tags to Display…") { m.showInspectorDisplaySettings = true }
                        Button("Select No Tags") { m.inspectorTracksIntent = true; m.inspectorFields = []; m.inspectorCleared = [] }
                    }
                    Button("Clear Selected") { m.clearCheckedTags(batch: false) }.disabled(m.inspectorFields.isEmpty)
                }
                if !Set(TagEditPatch.fields).isSubset(of: m.inspectorDisplayedFields) {
                    Text("Some tags are hidden. Use Edit ALL Tags to edit tags across selected files, including hidden tags, or use Purge to remove pre-defined tags.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView { VStack(spacing: 12) {
                    if m.inspectorDisplayedFields.isEmpty {
                        Text("No tags are displayed. Existing tags are unchanged.").foregroundStyle(.secondary)
                        Button("Choose Tags to Display…") { m.showInspectorDisplaySettings = true }
                    }
                    ForEach(TagEditPatch.fields.filter { m.inspectorDisplayedFields.contains($0) }, id: \.self) { name in tagField(name, batch: false) }
                } }
                if !m.inspectorPatch.summary.isEmpty { Text(m.inspectorPatch.summary).font(.caption).fixedSize(horizontal: false, vertical: true) }
                Button("Save Tags") { m.save() }.buttonStyle(.borderedProminent).disabled(!m.dirty)
                Button("Discard Changes") { m.loadSelection() }.disabled(!m.dirty)
                Text("Save tags before moving. Changing selection asks you to save or discard unsaved edits.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(18)
    }
}

// Read release labels from the packaged app so the toolbar and About stay in sync.
enum AppRelease {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    static var channel: String { Bundle.main.object(forInfoDictionaryKey: "TagCraftReleaseChannel") as? String ?? "Alpha" }
    static var shortLabel: String { version + " " + channel }
    static var noticeRelease: String { version + ":" + build }
    static var fullLabel: String { shortLabel + " (Build " + build + ")" }
    static let website = URL(string: "https://github.com/natsteff/TagCraft")!
}
struct AboutTagCraftView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            StatisticsBrandLogo(width: 220)
            Text("TagCraft Music Librarian").font(.title2.bold())
            Text("Version " + AppRelease.fullLabel)
                .textSelection(.enabled)
            Text(AppRelease.channel + " software. Test edits and moves on copies of your music files.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Link("TagCraft on GitHub", destination: AppRelease.website)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }.padding(30).frame(width: 420)
    }
}
