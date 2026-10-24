import Foundation
import AppKit

@main struct UIModelChecks {
    @MainActor static func main() async throws {
        checkColumnLayout()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TagCraft-UI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("visible.mp3"), b = root.appendingPathComponent("renamed.mp3")
        let hidden = root.appendingPathComponent("hidden.mp3")
        let bytes = Data(repeating: 0x42, count: 4096)
        try bytes.write(to: a); try bytes.write(to: hidden)
        let m = Model(); m.noticeAcknowledged = true; m.folder = root
        m.tracks = [Track(url: a, tags: Tags()), Track(url: hidden, tags: Tags())]
        m.selection = [a, hidden]; m.query = "visible"
        precondition(m.hiddenSelection == [hidden])
        precondition(m.selectionSummary.contains("1 hidden"))
        m.query = ""; precondition(m.hiddenSelection.isEmpty)
        m.requestSelection([a]); m.loadSelection()
        let manager = UndoManager(); manager.groupsByEvent = false; m.installUndoManager(manager)
        let stamp = FileJobs.fingerprint(a)
        manager.beginUndoGrouping()
        m.runPlans([FilePlan(source: a, destination: b, expectedSize: stamp.0, expectedDate: stamp.1)], label: "Rename Files")
        await wait(m); manager.endUndoGrouping()
        precondition(manager.canUndo && manager.undoActionName == "Rename Files")
        let movedBytes = try Data(contentsOf: b); precondition(movedBytes == bytes)
        manager.undo(); await wait(m)
        precondition(FileManager.default.fileExists(atPath: a.path) && manager.canRedo)
        manager.redo(); await wait(m)
        precondition(FileManager.default.fileExists(atPath: b.path) && manager.canUndo)
        // Changed files must not be silently moved by a stale undo.
        try Data([1,2,3]).write(to: b)
        manager.undo(); await wait(m)
        precondition(FileManager.default.fileExists(atPath: b.path) && !FileManager.default.fileExists(atPath: a.path))
        precondition(!m.failures.isEmpty && !manager.canRedo)
        // Failed saves preserve both pending edits and their original selection.
        m.tracks = [Track(url: a, tags: Tags())]; m.selection = [a]; m.loadSelection()
        m.draft.title = "Unsaved title"; var completed = false
        m.save(onSuccess: { completed = true }); await wait(m)
        precondition(!completed && m.dirty && m.draft.title == "Unsaved title" && m.selection == [a])
        // Refresh cannot silently replace an unsaved draft.
        m.scan(); precondition(!m.busy && m.dirty)
        // A successful save invokes the continuation only after the file is written.
        m.tracks = [Track(url: hidden, tags: Tags())]; m.selection = [hidden]; m.loadSelection()
        m.draft.title = "Saved fixture title"; completed = false
        m.save(onSuccess: { completed = true }); await wait(m)
        let savedTags = try ID3(Data(contentsOf: hidden)).tags
        precondition(completed && !m.dirty && savedTags.title == "Saved fixture title")
        var bulkFiles: [URL] = []
        for index in 1...7 {
            let url = root.appendingPathComponent("bulk-\(index).mp3")
            let tags = Tags(title: "Distinct title \(index)", artist: "Shared artist", year: "2000", track: "\(index)")
            let data = try ID3(bytes).writing(tags, original: bytes); try data.write(to: url)
            bulkFiles.append(url)
        }
        m.tracks = try bulkFiles.map { Track(url: $0, tags: try ID3(Data(contentsOf: $0)).tags) }
        m.selection = Set(bulkFiles); m.loadSelection()
        precondition(m.inspectorMixed.contains("Title") && m.inspectorMixed.contains("Track"))
        precondition(m.draft.title.isEmpty && m.draft.artist == "Shared artist")
        m.editTagField("Artist", value: "Shared artist", batch: false)
        precondition(m.inspectorFields.isEmpty && !m.dirty)
        m.editTagField("Artist", value: "Updated artist", batch: false)
        m.editTagField("Year", value: "2006", batch: false)
        precondition(!m.inspectorFields.contains("Title"))
        m.save(); await wait(m)
        for (index,url) in bulkFiles.enumerated() {
            let tags = try ID3(Data(contentsOf: url)).tags
            precondition(tags.title == "Distinct title \(index+1)" && tags.track == "\(index+1)" && tags.artist == "Updated artist" && tags.year == "2006")
        }
        m.selection = Set(bulkFiles); m.loadSelection()
        m.editTagField("Artist", value: "", batch: false)
        precondition(m.inspectorFields.contains("Artist") && m.inspectorCleared.contains("Artist"))
        precondition(m.inspectorPatch.applying(to: m.selected[0].tags).title == m.selected[0].tags.title)
        m.loadSelection()
        m.editTagField("Title", value: "Temporary input", batch: false)
        m.editTagField("Title", value: "", batch: false)
        precondition(m.inspectorFields.contains("Title") && m.inspectorCleared.contains("Title"))
        m.loadSelection(); m.beginBatch()
        m.editTagField("Artist", value: "", batch: true)
        precondition(m.batchFields.contains("Artist") && m.batchCleared.contains("Artist"))
        m.editTagField("Artist", value: "Updated artist", batch: true)
        precondition(!m.batchCleared.contains("Artist"))
        m.checkTagField("Title", enabled: true, batch: true) // Checked blank mixed title must still be skipped.
        m.editTagField("Year", value: "2007", batch: true)
        m.applyBatch(); await wait(m)
        for (index,url) in bulkFiles.enumerated() {
            let tags = try ID3(Data(contentsOf: url)).tags
            precondition(tags.title == "Distinct title \(index+1)" && tags.year == "2007")
        }
        m.selection = Set(bulkFiles); m.loadSelection()
        m.checkTagField("Title", enabled: true, batch: false); m.clearCheckedTags(batch: false)
        precondition(m.inspectorPatch.effective == ["Title"] && m.inspectorPatch.cleared == ["Title"])
        m.loadSelection() // Leave the test without pending removals.
        print("UI model checks passed: hidden scope, native file Undo/Redo, changed-file refusal, failed-save draft preservation and refresh protection.")
    }
    @MainActor static func checkColumnLayout() {
        _ = NSApplication.shared
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 200))
        let header = SelectionHeader(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        table.headerView = header
        for title in ["✓", "Filename", "Artist", "Lyrics", "Year"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
            column.title = title; column.minWidth = title == "✓" ? 30 : 45
            column.maxWidth = title == "✓" ? 30 : 1200
            column.width = title == "✓" ? 30 : 140
            table.addTableColumn(column)
        }
        let selection = table.tableColumns[0], filename = table.tableColumns[1]
        let artist = table.tableColumns[2], lyrics = table.tableColumns[3]
        WorkspaceTableLayout.configure(table, visible: ["Filename", "Artist", "Year"])
        precondition(table.columnAutoresizingStyle == .noColumnAutoresizing && table.allowsColumnResizing)
        precondition(selection.resizingMask.isEmpty && artist.resizingMask == .userResizingMask)
        precondition(lyrics.isHidden && !filename.isHidden)
        precondition(header.isSelectionClick(NSPoint(x: 10, y: 10)))
        precondition(!header.isSelectionClick(NSPoint(x: header.headerRect(ofColumn: 0).maxX - 2, y: 10)))
        filename.width = 280
        let artistWidth = artist.width
        table.setFrameSize(NSSize(width: 600, height: 200)); table.tile()
        precondition(filename.width == 280 && artist.width == artistWidth)
        WorkspaceTableLayout.fit(table, tracks: [])
        precondition(filename.width >= filename.minWidth && filename.width < 280)
        let hiddenWidth = lyrics.width
        let track = Track(url: URL(fileURLWithPath: "/tmp/" + String(repeating: "Long filename ", count: 50) + ".mp3"), tags: Tags(title: "Title", artist: "A reasonably long artist name"))
        WorkspaceTableLayout.fit(table, tracks: [track])
        precondition(filename.width <= 520 && artist.width > artistWidth && lyrics.width == hiddenWidth)
        WorkspaceTableLayout.configure(table, visible: ["Filename", "Lyrics"])
        WorkspaceTableLayout.fit(table, tracks: [track])
        precondition(!lyrics.isHidden && artist.isHidden && lyrics.width >= 80)
        WorkspaceTableLayout.configure(table, visible: [])
        precondition(!filename.isHidden && selection.isHidden == false && lyrics.isHidden)
        precondition(WorkspaceTableLayout.fittedWidth(title: "Lyrics", values: [String(repeating: "lyrics\n", count: 2000)]) <= 360)
        // Later refresh/configuration must preserve manual widths.
        filename.width = 350
        WorkspaceTableLayout.configure(table, visible: ["Filename"])
        precondition(filename.width == 350)
        print("Column checks passed: native resize policy, divider hit testing, visibility, empty/populated auto fit, width caps and manual width retention.")
    }
    @MainActor static func wait(_ m: Model) async {
        while m.busy { try? await Task.sleep(for: .milliseconds(10)) }
    }
}
