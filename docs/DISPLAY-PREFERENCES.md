# Display preferences — Build 5

Settings → Tags to Display in Tag Inspector… shows an alphabetical checkbox list of the 20 supported editable fields. Select All and Select None are supported, including persistence of an empty choice. Select from Purge configuration uses frame mappings to take the inverse of the current Purge selection, including Year / Recording Date and the combined Lyrics group. This copies the selection once; it neither updates Purge nor links later changes. Artwork remains separately available. Save or discard pending edits before hiding their fields; Done is blocked until those edits are resolved or the fields remain shown.

Customize Columns… is available beside workspace selection controls, in Settings, and in View. Every supported tag is offered, even if hidden from the inspector. Choices are grouped into Shown in Tag Inspector and Hidden from Tag Inspector; both groups are alphabetical. Filename and Status appear in a separate file-columns section; Filename and selection remain available. Optional columns support Select All, Select None and Restore Defaults. Tag cells retain sort support. Long lyrics are displayed on one line; the inspector provides multiline editing.

The two saved preferences are independent. Visibility changes do not write music files, select tags for editing, change Purge configuration or clear tags. macOS 14.0 compatibility uses native NSTableColumn visibility with stable SwiftUI column definitions.

Automated checks cover alphabetic group completeness, frame-based inverse mapping, persistence of Select None, independent preferences, intentional deletion in both editors and preservation of untouched mixed tags.

## Column sizing — Build 7

The workspace Columns menu provides Customize Columns… and Auto Fit Columns. Auto Fit Columns is also in View. It measures headers and the current filtered rows for displayed columns, with space for sort indicators. Empty results fit to headers. Filename auto-fit is capped at 520 points, Lyrics at 360 and other data columns at 320; manual dragging can exceed those auto-fit caps within each column’s range. Lyrics remain a single-line preview. Hidden columns are not auto-fitted, and fitting does not change column visibility, sorting, selection, inspector preferences or music files.

Data columns resize independently through native header dividers. Track, Year and Status now have flexible ranges rather than fixed widths. Automatic redistribution is disabled, so resizing a data column does not intentionally expand its neighbours. Horizontal scrolling handles total widths greater than the workspace. The selection column remains fixed; its header’s divider edge is passed to AppKit rather than toggling track selection. Manual widths are kept during ordinary bridge configuration; persistent widths across app restarts are not implemented.

Verification uses disposable native table checks and a separate SwiftUI workspace preview with fictional in-memory tracks and isolated preference storage. These checks do not establish music writer safety.
