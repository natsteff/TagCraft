# New TagCraft features

## Clean
Open **Settings → Clean Rules…** to configure whitespace, underscores, separator dots, capitalization, track-prefix removal, and trailing-label removal. Rules save automatically. Add artist names, acronyms, and exact spellings to the exceptions list. Dotted initials and decimal numbers are protected; characters forbidden in filenames still become underscores.

Trailing-label removal starts off. Its default list includes Official Video, Official Music Video, Official Audio, Lyrics, and Lyric Video. It only removes a configured label at the end after a dash or in brackets. Live, Remix and Acoustic remain unless you explicitly add them. Review every change; local rules cannot infer every artist's preferred spelling.

Click **Clean** for a preview. Red marks removed/replaced characters and green marks new characters. The preview explains the rules used. Check or uncheck individual files, or Include All / Exclude All. Files with errors are skipped.

## Preparation workflows
Open **Settings → Preparation Workflows…** or **Workflow** in the action bar. Enable the steps you need, in this order:

1. Clean filename.
2. Extract tags from the resulting filename.
3. Purge selected fields.
4. Rename from the resulting tags.
5. Move to the library.

Copy your current Clean rules, extraction mask/grouping settings, and Purge selection into the preset using the provided buttons. Name the preset and choose Save Preset. Load, edit, or delete it later. Presets retain their own rule settings.

Preview Files builds one combined plan without changing files. Review filename, tag, and destination changes and exclude individual files. Purging an artist/title needed by a later rename or move flags that file as ineligible. Apply executes the approved plan. Tag changes create full backups; if a later move step fails, the original tag contents are restored from the backup. Undo File Action reverses the latest rename/move during the current session; tag restoration still uses backup files.

## Artist matching and duplicate checks
**Move to Library** reads the existing artist folder names and suggests near matches for capitalization, punctuation, spacing, accents, and small spelling differences. The preview's Artist Folder dropdown lets you choose an existing name or keep the original. Suggestions never silently alter tags.

In that preview (or a workflow preview with a move step), **Check Against Library for Duplicates** runs a manual, cancellable content check. It compares incoming files with the library and each other. Matching files receive yellow warnings and are excluded by default; you can review and include them explicitly.

**Library Tools → Check Library Duplicates…** checks selected files against the library. With no selection, it reports duplicates within the entire library. This report never deletes files. Checks hash compressed audio while ignoring leading ID3v2 and trailing ID3v1 tags, so tag and filename differences do not conceal identical audio payloads. Differently encoded versions of a recording require audio fingerprinting and are not detected. Unreadable-file counts appear in the report. Nothing is uploaded.

## Artwork and technical details
Select one track and choose **Artwork & Details…** in the inspector. View its artwork, duration, estimated bitrate, sample rate, file size and ID3 version. Set Artwork accepts JPEG or PNG under 20 MB, replacing embedded pictures with one front cover. Remove Artwork clears all embedded pictures. Both operations create full backups.

## Background work and browsing
Scans, writes, moves, undo, workflow planning, duplicate checks, and library statistics run off the main UI thread. Progress and Cancel appear during work. A file already being written/moved finishes before cancellation stops the remaining queue. Failed files are listed in the status area with a Retry Failed action; files changed since preview require a new preview.

Use breadcrumb buttons, Recent Folders, or drag a folder into the window to browse. Dropping a file opens its parent folder. Automatic Refresh uses macOS folder events, including nested folders, and respects Include Subfolders. It pauses while jobs run or inspector edits are unsaved. Include Subfolders remains off by default.

## Manual library statistics
Open **Library Tools → Library Statistics…**. Nothing scans automatically. Choose **Update Library Statistics** to scan the full defined library recursively, regardless of the source folder's Include Subfolders setting.

The dashboard shows total MP3 tracks, distinct tagged artists, albums (artist + album combinations), total file size in decimal GB/TB, unreadable-tag count, and sortable/filterable breakdowns by artist, genre and year. Missing/unsupported tags appear under Unknown; spelling variants count separately. Hidden backup folders are excluded.

Optionally enable **Include duration, bitrate and sample-rate statistics (slower)** before updating. This adds total playback duration and audio-format breakdowns using AVFoundation. Files whose audio details cannot be read are reported. Estimated bitrate may vary for VBR files.

Updates show progress and can be cancelled. The last complete snapshot is saved locally and dated; cancelling or an incomplete traversal keeps the previous complete snapshot. A different library displays no cached results until manually updated. Large libraries can take a long time, especially with audio details or content hashing enabled.

## Validation and limitations
Release compilation and standalone regression checks pass, including end-to-end workflow writes, audio preservation, artwork data changes, exact duplicate hashing, case-only renames, statistics totals, collisions, cancellation, stale previews and rollback. AVFoundation duration/sample-rate extraction was also checked using an MP3 fixture. Full live-window interaction verification is still pending.

Persistent operation history/recovery and online music identification were not part of this selected feature batch. Backups remain the recovery method for tag changes.

**Library Tools** is the first action-bar item. **Settings** is the final item, containing Clean Rules, Preparation Workflows, Tags to Purge, Change Library and its current full path, Automatic Refresh, and Action Bar Display. The sidebar and its toggle are removed. Open Workspace contains Open Workspace Folder, recent workspace paths, and Clear Recent Workspaces. Library Tools shows the destination library path in its menu and hover hint. Organization notes appear in the move preview. The current workspace name, full path, and breadcrumbs remain above the file list.

Workspace restoration now uses the explicit `local.tagcraft.musiclibrarian.preferences` suite, with a version-independent `workspace-session.json` backup in Application Support/TagCraft Music Librarian. Existing preferences are migrated on first launch. Recent workspaces and the destination library are retained independently of app version and executable name; clearing recents does not clear the current workspace.


## Clean and Magic separation
Clean now prepares the raw filename only. It ignores existing tags, supports title-only filenames, and preserves field order. Delimiter normalization converts obvious separators to ` - `, while protected artist spellings, dotted initials, decimals and known hyphens remain. Unspaced letter-to-letter hyphens can be ambiguous and receive review warnings. Turn delimiter normalization off in Clean Rules if needed.

Magic starts a combined preview of Clean → extraction → rename. Choose the input layout or custom input mask in that preview. Its output defaults to Artist - Title.mp3. It neither purges nor moves files. No tags or filenames change until Apply. The general Workflow editor remains available for saved/custom sequences.

The action bar now uses a `»` More menu for actions that do not fit, rather than horizontal scrolling. The logo precedes Library Tools and the extra left inset is removed. Hover hints are non-interactive overlays, not popovers; they disappear on a mouse click and do not take focus away from dropdown menus. Live interaction verification remains pending.


## Mini player and action order
Playback lives at the bottom of the track list, above the status line. The mini player shows artist/title (filename fallback), Previous, Play/Pause, Stop, Next, elapsed/total time and a draggable seek bar. Scrubbing also works while paused. Stop returns to the beginning. Next/Previous and automatic advance use the current filtered and sorted list, without changing the edit selection. The actively playing filename appears blue; paused and stopped tracks use normal text with no inline icon. Changing the edit selection does not interrupt playback; use the track's Play context action to explicitly play another selected file.

Processing actions are ordered Magic, Clean, Get Tags from Filename, Edit Selected Tags, Rename from Tags, Move to Library, followed by Purge and Workflow. Magic and Workflow remain separate. Play/Stop no longer consume action-bar space; hidden actions still use the More menu.

Mini-player controller checks passed for loading, paused seeking, next/previous ordering, filename fallback and Stop using an MP3 fixture. Audible playback and automatic advance could not be verified because the test environment did not provide an audio output.

## Version 0.4.0

Magic now analyzes filename structure, cleanup rules, spelling exceptions, existing tags, library artist names and batch evidence locally. Its combined review lets you edit inferred artist, title and track, compare alternatives, and review filename changes before applying. Ambiguous files are excluded until explicitly included. Dictionary clues do not turn every unknown word into an acronym. Individual actions and configurable Workflow remain available.

The inspector always shows an embedded-artwork thumbnail or an explicit empty/mixed state. Edit Tags in Selected Files shows common artwork for checked files and supports choosing or removing artwork across those files, independently of text-field changes. Changes use the existing backup process.

Magic uses a wand icon; Clean uses a broom. Processing actions are ordered Magic, Clean, Purge, Get Tags from Filename, Edit Selected Tags, Rename from Tags, and Move to Library, including toolbar overflow.

Build 29: updated TagCraft application icon without the subtitle, with a new icon resource name; toolbar subtitle uses native text rendering for clarity.

Build 32: optional right-aligned toolbar waveform appears only when the complete action bar plus branding fits; all actions without branding are tried before overflow. Full logo on the initial workspace welcome view; subdued waveform for the empty inspector and missing artwork, with explicit artwork-state labels retained. Statistics retains its full right-aligned logo.

Build 33: a brief 1.5-second logo splash appears at launch while workspace restoration begins, followed by a short fade. The empty workspace welcome logo remains. Workspace filtering is always visible beside the folder information, with a clear button; its toolbar button and popover were removed.

Build 34: launch splash uses a separate centered 420×340 borderless panel, independent of saved workspace-window dimensions. Main windows are hidden and ignore clicks during the 1.5-second splash, then restored without changing their saved frames. The previous main-content overlay was removed to prevent toolbar fragments showing above it. The empty-workspace welcome view remains.

Build 35: Workflow preview detects files whose filename, tags, purge fields and destination need no changes, labels them No change needed and excludes them from Apply. Actionable rows list actual rename, move, tag update or purge actions instead of always saying Will rename.

## Version 0.5.0 — review, artwork and library health

Implemented requested items 1, 5, 12, 13, 14, 16, 17 and 18 from the improvement list:

1. Magic excludes unchanged tags/filenames from Apply and displays No change needed.
5. Magic uses conservative album-folder, known-artist, consecutive-track and CD/Disc clues. Featured-credit placements and ungrouped recording-version suffixes are alternatives. Inferred album names require review; existing metadata is retained where present. Album and disc are editable in the preview. Context comes from selected files and their folder paths, not an automatic recursive scan.
12. Batch fields show common values or Multiple values, recalculate untouched fields as checked tracks change, and let Common Fields select only shared values.
13. Artwork inspection exposes all embedded pictures, image dimensions/format/size, export, JPEG/PNG drops and optional downscaling. Replacing a front cover preserves other types unless explicitly replacing all. Existing full backups remain in use.
14. A cancellable workspace quality check identifies missing fields/artwork, invalid track/disc totals, suspicious years, whitespace, artist variants and inconsistent album artists. Corrections require explicit selection and reject stale field values.
16. Statistics includes health breakdowns and detailed health reports. Bitrate findings require the optional audio scan; unreadable tags are reported separately rather than counted as missing values.
17. Manual updates reuse unchanged cached tag/audio records, enumerate current files to remove deleted entries, retry unreadable records, and display elapsed/rate/approximate remaining time. Reuse can be disabled. No scan is automatic; cancellation/failure preserves the previous saved snapshot.
18. CSV exports cover totals, breakdowns, inventories, quality/health and the last duplicate report. Snapshot-based reports include location/date context. CSV quotes commas, quotes and newlines correctly.

Regression checks include no-op Magic, contextual inference, protected recording labels, mixed tags, quality suggestions, snapshot/cache changes/deletions/cancellation, real MP3 audio-statistics reuse, CSV roundtrips, multiple-picture preservation and artwork resizing. Live UI interaction review remains pending.

Build 39: all workspace status messages and progress appear right-aligned in a fixed-height footer below the mini-player. Cancellation, error details and retry stay in that footer. Removed header/list-area progress and error rows to prevent layout jumps during short operations.

Build 40: spare action-bar space contains a right-aligned strip of whole waveform tiles, joined at their flat ends without spacing. Tile count rounds down, leaving insufficient space blank; actions retain priority and the strip disappears before overflow is needed.

Build 41: restored a single far-right-aligned toolbar waveform. It yields to actions and disappears before overflow is required; repeating waveform strip removed.

Build 42: footer details and file counts are left-aligned again; only active progress and Cancel occupy the right. Footer height remains fixed. UI-only change; safety-review findings remain unresolved.

Build 43: library scan elapsed and approximate remaining time use H:MM:SS, including the discovery phase.

## Version 0.5.1 — SQLite statistics

- Completed statistics and per-file caches now use local SQLite, with indexed records and SQL aggregation. Unchanged MP3 records are referenced again without rewriting their metadata rows. Only summary groups are loaded at startup; inventory/health details are queried on demand.
- Manual scans checkpoint every 50 processed files, retaining the previous completed snapshot until atomic publication. Subsequent manual updates can reuse interrupted work; deleted entries are removed only from a successfully completed report. Cache writes never modify MP3s.
- One-time JSON migration uses a verified temporary database, leaves the original JSON untouched, and refuses publication if the JSON changed during import. Normal SQLite initialization is separate from the removable legacy migration hook.
- Tests cover 32,546 synthetic migration records, Unicode/embedded-NUL metadata, JSON preservation, idempotency, failed migrations, future-schema refusal, unchanged-version reuse, summary/health parity, resumed first/update scans, changed/deleted/new files, forced rereads, database rollback, exclusive scan locking and optional audio-cache enrichment.
- Elapsed/remaining display uses H:MM:SS and the rate is labeled Avg. processing rate: N tracks/sec. UI interaction testing remains pending. Music-file safety-review findings remain unresolved.

Build 46: clicking a Health row opens only that exact issue type, using a filtered SQLite query instead of loading the entire report. The review dialog includes an issue-type selector and file/text filter; changing filters clears checks, retains typed replacements and limits Apply to checked rows in the current view. Counts show issues and distinct files. Library Overview now labels the tabs from above; each category starts sorted by descending track count. Unknown is not specially pinned.
