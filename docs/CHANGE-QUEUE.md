# Change queue

## Pending — 0 items

No pending requested changes.

## Release snapshot — 0.7.0 Beta (Build 1), October 23, 2026

Publication target: `v0.7.0-beta`. Nate explicitly approved README review/update, refreshing screenshots, publishing the latest app, and the Alpha-to-Beta transition. This minor release collects the locally implemented changes below since published 0.6.0; per-version publication builds start at 1. The README describes current features and retains all material unresolved music-write limitations. Beta is an owner-approved channel change, not evidence that writes to original libraries are safe.

Ten direct real-app captures replace the seven original gallery JPEGs and add Edit ALL Tags, tag visibility and column settings. Only fictional demo content is shown; 8 workspace and 24 library MP3s are hash-verified unchanged. Original workspace/library/settings/statistics were restored after capture, retaining Nate’s actual notice acknowledgment. Capture versions/history are in SCREENSHOTS.md. Offline notice supplement 1.1 changes only release terminology and was regenerated from Legal sources; LICENSE is unchanged.

Release validation: core and column/UI-model regression checks, release compilation, shared metadata/offline-resource gates, ad-hoc signature, read-only DMG inspection and SHA-256 checksum pass. Release asset: `TagCraft-0.7.0-beta-macOS-arm64.dmg`, containing the app, Applications shortcut and metadata-generated INSTALL.txt. No Intel asset, notarization or clean-machine installation test is claimed. Full accessibility, audible playback and unsaved-edit close/reopen acceptance remain incomplete.

## Implemented locally — Build 8, October 23, 2026

1. Restored native macOS close, minimize and zoom/full-screen controls using the standard titled window. Removed the hidden-window-toolbar modifier, top safe-area bypass and native title-hiding override. The custom labeled command ribbon remains below the native title bar.

Verification: local package compiles and ad-hoc signature verification and source/packaged release gates pass. Column/UI-model checks pass. An isolated live SwiftUI workspace preview exposes all three native control accessibility elements; zoom, minimize/restore and full-screen entry/exit were exercised, along with the native close button. No existing music files or acknowledgment records were modified. Full unsaved-edit window-close/reopen behavior has not been acceptance-tested. Local 0.7.0 Alpha Build 8 only; not published.

## Implemented locally — Build 7, October 23, 2026

1. Changed the hidden-tags reminder to “use Purge to remove pre-defined tags”, distinguishing Purge configuration from inspector checkboxes. Also corrected the toolbar hover help to explain editing supported hidden tags.
2. Enabled independent native data-column resizing, made Track/Year/Status widths flexible, and kept selection-header divider clicks with AppKit. The bridge reapplies visibility and resizing policy after SwiftUI reconciles the table, including startup, without resetting manual widths during ordinary updates.
3. Added Auto Fit Columns under the workspace Columns menu (alongside Customize Columns…) and View. Sizes use headers/current filtered rows, with bounded filename/lyrics/other widths; hidden columns and selection are preserved. Empty results size from headers. Manual widths are not persisted across app restarts.

Verification: disposable native-column and UI-model checks pass. Isolated live SwiftUI preview checks covered startup hidden-column visibility, right/left divider dragging, alternate visible-column sets including Lyrics, Auto Fit recovery, empty filtered results, the selection header and reminder text. Only fictional in-memory tracks and disposable test fixtures were used; no existing music files were written. Preview/test preferences use an isolated suite. Existing alpha music-write safety limitations remain unresolved. Local build only; not published.

## Implemented locally — Build 6, October 23, 2026

1. Renamed the toolbar action, overflow action name, matching menu command, operation label and editor heading to “Edit ALL Tags” (editor heading: “Edit ALL Tags in Selected Files”). Toolbar help explains that supported hidden tags are included.
2. Renamed the inspector menu to “Tags”, with “Select All Tags” and “Select No Tags”. Selection behavior is unchanged and remains limited to displayed inspector tags.
3. Added a reminder above the inspector inputs when any supported editable tag is hidden. It directs users to Edit ALL Tags for bulk editing, including hidden tags, or Purge for selected tag removal. The reminder is omitted when all supported tags are displayed.

UI model regression checks pass. Live visual verification of these wording changes has not been performed. No music files were edited for this change set.

## Implemented locally — Build 5, October 23, 2026

- Deliberately erasing content keeps the field checked and marks it for removal in both editors. Untouched empty and mixed fields remain unchanged.
- Persistent Tags to Display in Tag Inspector with Select All, Select None, and a one-time frame-mapped inverse of Purge configuration. Hiding pending edits is blocked until resolved.
- Customize Columns offers all 20 supported tag fields in alphabetical Shown in Tag Inspector / Hidden from Tag Inspector groups. Column and inspector selections are independent; Filename and selection remain available.
- Automated regression suites pass, and the local app is packaged as 0.7.0 Alpha Build 5. Live UI checks passed for custom columns, persistent inspector visibility, the empty-inspector state, deliberate deletion and Discard restoring unchecked fields. Display preferences were restored; no music files were written during live checks. See docs/DISPLAY-PREFERENCES.md.

## Completed locally — Build 4, October 23, 2026

- Shared-values inspector across every selected track; distinct Multiple values placeholders.
- One inclusion checkbox per field, automatically checked for nonempty edits. Blank/mixed/unchecked fields are preserved in both editors; typing then deleting does not clear tags.
- Clear Selected explicitly marks checked tags for removal, with per-field indicators, a summary and confirmation before writes.
- Lyrics (USLT) read/write/multiline editing and explicit removal in ID3v2.3/v2.4. Additional language entries survive ordinary edits; synchronized lyrics are preserved.
- Disposable seven-file model regression covers distinct Title/Track preservation for Artist/Year-only edits and checked blank fields. Existing music files were not restored or rewritten.

## Completed locally — October 23, 2026

- Build 3: removed the compact toolbar’s eight-action cap. Both orderings try all actions first and then progressively fewer, so actions expand and collapse with available width.

## Completed October 22, 2026

- Pushed: latest wider workspace image and Library Health in the main README (50d6e13).
- Implemented locally in 0.7.0 Alpha Build 2: all high- and medium-priority UI findings. See [UI improvements and verification](UI-IMPROVEMENTS.md).
- AGPL-3.0 version 3 only and License & Usage Notice; offline documents, acknowledgment migration and tests.

Builds 2–8 above were local Alpha iterations collected into the 0.7.0 Beta Build 1 release snapshot. Lower-priority startup interruptions and the additional Ready/Magic/Workflow terminology observations were not authorized as part of this change set.
