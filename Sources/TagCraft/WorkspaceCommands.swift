import SwiftUI
import AppKit

@MainActor extension Model {
    func installUndoManager(_ manager: UndoManager) {
        guard fileUndoManager !== manager else { return }
        for token in undoObservers { NotificationCenter.default.removeObserver(token) }
        fileUndoManager = manager
        undoObservers = [Notification.Name.NSUndoManagerDidCloseUndoGroup, Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.undoRevision += 1 }
            }
        }
        undoRevision += 1
    }
    func registerFileUndo(_ plans: [FilePlan], label: String) {
        guard let manager = fileUndoManager else { return }
        manager.registerUndo(withTarget: self) { [weak manager] model in
            guard let manager, !model.busy else { return }
            // Capture the inverse while UndoManager is undoing/redoing, so it is
            // registered on the correct stack. A rename preserves size/date.
            let reciprocal = plans.map { plan in
                FilePlan(source: plan.destination, destination: plan.source,
                         expectedSize: plan.expectedSize, expectedDate: plan.expectedDate)
            }
            model.registerFileUndo(reciprocal, label: label)
            model.runPlans(plans, label: (manager.isUndoing ? "Undo " : "Redo ") + label, registerUndo: false)
        }
        manager.setActionName(label)
        undoRevision += 1
    }
}

struct WorkspaceCommands: Commands {
    @ObservedObject var model: Model
    @AppStorage("showInspector", store: AppPreferences.defaults) private var showInspector = true
    @AppStorage("inspectorWidth", store: AppPreferences.defaults) private var inspectorWidth = 405.0
    @AppStorage("compactToolbar", store: AppPreferences.defaults) private var compactToolbar = true
    private var blocked: Bool { !model.noticeAcknowledged || model.busy }
    private var noFiles: Bool { blocked || model.selection.isEmpty || model.dirty }
    private var activeUndoManager: UndoManager? { NSApp.keyWindow?.firstResponder?.undoManager ?? model.fileUndoManager }
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(activeUndoManager?.undoMenuItemTitle ?? "Undo") { activeUndoManager?.undo() }
                .keyboardShortcut("z").disabled(blocked || activeUndoManager?.canUndo != true)
            Button(activeUndoManager?.redoMenuItemTitle ?? "Redo") { activeUndoManager?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(blocked || activeUndoManager?.canRedo != true)
        }
        CommandGroup(after: .newItem) {
            Button("Open Workspace…") { model.pick() }.keyboardShortcut("o").disabled(blocked)
            Button("Refresh Workspace") { model.scan() }.keyboardShortcut("r").disabled(blocked || model.folder == nil || model.dirty)
        }
        CommandGroup(after: .saveItem) {
            Button("Save Tags") { model.save() }.keyboardShortcut("s").disabled(blocked || !model.dirty)
        }
        CommandMenu("Tracks") {
            Button("Magic…") { model.beginMagic() }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(noFiles)
            Button("Clean Filenames…") { model.previewClean() }.disabled(noFiles)
            Button("Get Tags from Filename…") { model.previewExtract() }.disabled(noFiles)
            Button("Edit ALL Tags…") { model.beginBatch() }.keyboardShortcut("e").disabled(noFiles)
            Button("Rename from Tags…") { model.previewRename() }.disabled(noFiles)
            Button("Purge Tags…") { model.previewPurge() }.disabled(noFiles)
            Divider()
            Button("Move to Library…") { model.prepareMovePreview() }.disabled(noFiles)
            Button("Preparation Workflows…") { model.showWorkflow = true }.disabled(blocked)
            Divider()
            Button("Select All Visible Tracks") { model.requestSelection(model.selection.union(model.filtered.map(\.url))) }.disabled(blocked)
            Button("Clear Track Selection") { model.requestSelection([]) }.disabled(blocked)
            Button("Clear Hidden Selection") { model.requestSelection(model.selection.subtracting(model.hiddenSelection)) }.disabled(blocked || model.hiddenSelection.isEmpty)
            Button("Reveal Selected Files in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.selected.map(\.url)) }.disabled(blocked || model.selection.isEmpty)
            Button("Play Selected Track") { model.play() }.disabled(blocked || model.selection.isEmpty)
        }
        CommandMenu("Library") {
            Button("Library Statistics…") { model.showStatistics = true }.disabled(blocked)
            Button("Check Library Duplicates…") { model.checkDuplicates() }.disabled(blocked || model.library == nil)
            Button("Check Workspace Tag Quality…") { model.checkTagQuality() }.disabled(blocked || model.tracks.isEmpty)
            Button("Export Last Duplicate Report…") { model.exportDuplicateReport() }.disabled(blocked || model.duplicateResults.isEmpty)
            Divider()
            Button("Change Library…") { model.pick(library: true) }.disabled(blocked)
            Button("Library Structure…") { model.showLibraryStructure = true }.disabled(blocked)
            Button("Clean Rules…") { model.showCleanSettings = true }.disabled(blocked)
            Button("Tags to Purge…") { model.showPurgeSettings = true }.disabled(blocked)
        }
        CommandGroup(after: .sidebar) {
            Button("Customize Columns…") { model.showColumnSettings = true }.disabled(blocked)
            Button("Tags to Display in Tag Inspector…") { model.showInspectorDisplaySettings = true }.disabled(blocked)
            Button("Auto Fit Columns") { model.autoFitColumns() }.disabled(blocked)
            Toggle("Show Tag Inspector", isOn: $showInspector).keyboardShortcut("i", modifiers: [.command, .option])
            Button("Narrower Tag Inspector") { inspectorWidth = max(300, inspectorWidth - 40) }.keyboardShortcut("[", modifiers: [.command, .option]).disabled(!showInspector)
            Button("Wider Tag Inspector") { inspectorWidth = min(700, inspectorWidth + 40) }.keyboardShortcut("]", modifiers: [.command, .option]).disabled(!showInspector)
            Toggle("Compact Toolbar", isOn: $compactToolbar)
        }
    }
}
