# UI improvements — 0.7.0 Alpha Build 2

The requested README image replacement and Library Health placement were pushed in commit 50d6e13. The following changes were implemented locally in Alpha Build 2 and are included in the 0.7.0 Beta Build 1 release snapshot.

## High-priority changes

- User-driven selection changes (rows, checkboxes, selection controls and menu commands) ask Save Changes / Discard Changes / Cancel when the inspector is dirty. Saving changes selection only after the write succeeds. Failed saves retain pending edits and selection. Refresh refuses to replace a dirty inspector. Quitting offers save/discard/cancel and refuses to interrupt an active file operation.
- Workspace counts identify selections hidden by filtering. Clear Hidden Selection is available in the workspace and Tracks menu. Operation reviews show selection scope; execution requires explicit confirmation when its plans include hidden selections. Cancelling this confirmation returns to the preview without applying changes.
- File, Tracks and Library menus expose workspace and file commands. Standard Edit Undo/Redo and Command-Z / Shift-Command-Z use the native undo manager, preserving text editing. Successful renames/moves register reversible path operations. When an operation also writes tags, its undo is explicitly labeled Filenames Only. Metadata restoration still requires backups. Undo/Redo refuses changed sources and conflicting destinations; failed reversals clear file reversal entries rather than offer an invalid redo.

## Medium-priority changes

- A compact toolbar groups navigation, preparation/editing and library controls, with the remaining actions under More. Full/compact and icon/text choices remain available. All actions remain accessible through menus regardless of toolbar overflow.
- Toolbar text increases from 10 to 12 points. Selection scope uses callout text and primary color when hidden selections exist. Review dialogs use flexible dimensions and resizable sheets while retaining minimum widths for their forms. Inspector width adapts to available space and can be hidden to give the table more room.
- View provides inspector visibility and width commands. Option-Command-I toggles it; Option-Command-[ and Option-Command-] resize it. The divider exposes accessibility increment/decrement actions and its effective width. Playback, filter clearing and custom toolbar actions have explicit accessible names.

## Verification

- App compiles for macOS 14+; bundle metadata, shared version labels, offline license/notice resources and ad-hoc signature are checked.
- Checks/run.sh covers existing filename, tag, scanner, SQLite, update-check, symlink and acknowledgment behavior.
- Checks/run-ui.sh compiles the actual model with an alternate check entry point. Disposable fixtures exercise hidden scope, native rename Undo/Redo, externally changed-file refusal, failed-save draft retention, refresh protection and successful-save continuation.
- Live sample-workspace checks: selection-change prompt, Cancel preserving the draft and selected track, hidden-selection workspace/preview text, menu access, Command-Z in a text field, inspector keyboard toggle and accessibility width adjustment, and hidden-file execution confirmation followed by Cancel. No sample music changes were applied in live checks.

This is targeted keyboard/accessibility verification, not a complete VoiceOver or contrast certification. Existing alpha tag-write limitations documented in the README and usage notice remain unresolved.
