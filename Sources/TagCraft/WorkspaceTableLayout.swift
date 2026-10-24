import AppKit

/// Keep native manual resizing independent of neighbouring and hidden columns.
@MainActor enum WorkspaceTableLayout {
    static func configure(_ table: NSTableView, visible: Set<String>) {
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnResizing = true
        table.enclosingScrollView?.hasHorizontalScroller = true
        for (index, column) in table.tableColumns.enumerated() {
            if index == 0 {
                column.resizingMask = []
                column.isHidden = false
            } else {
                column.resizingMask = .userResizingMask
                let hidden = column.title != "Filename" && !visible.contains(column.title)
                if column.isHidden != hidden { column.isHidden = hidden }
            }
        }
    }

    static func fittedWidth(title: String, values: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        // Include header padding and the native sort indicator.
        var width = (title as NSString).size(withAttributes: [.font: font]).width + 36
        for value in values {
            // Lyrics and other multiline tags are single-line cells. Bound measurement
            // work per cell as well as the resulting width for unusually large tags.
            let text = String(value.prefix(512)).replacingOccurrences(of: "\n", with: " · ")
            width = max(width, (text as NSString).size(withAttributes: [.font: font]).width + 24)
        }
        let minimum: CGFloat = title == "Filename" ? 100 : (title == "Lyrics" ? 80 : 60)
        let maximum: CGFloat = title == "Filename" ? 520 : (title == "Lyrics" ? 360 : 320)
        return ceil(min(maximum, max(minimum, width)))
    }

    static func fit(_ table: NSTableView, tracks: [Track]) {
        for column in table.tableColumns.dropFirst() where !column.isHidden {
            let values = tracks.map { track in
                switch column.title {
                case "Filename": return track.filename
                case "Status": return track.status
                default: return track.tags.value(column.title)
                }
            }
            column.width = min(column.maxWidth, max(column.minWidth, fittedWidth(title: column.title, values: values)))
        }
        table.tile()
        table.headerView?.needsDisplay = true
    }
}
