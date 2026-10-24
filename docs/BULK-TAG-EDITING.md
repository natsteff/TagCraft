# Shared values and explicit tag removal — Build 5

The inspector displays only values shared by every selected track, including empty common values. Different values show the Multiple values placeholder. This applies to standard fields, additional fields and Lyrics.

Each field has one inclusion checkbox. Entering a nonempty value checks it automatically. Unchecked fields, blank inputs and untouched mixed fields retain each file’s own value. Deliberately deleting a field’s nonempty content keeps it checked and marks it for removal. Untouched empty/mixed fields remain preserved. The summary lists fields that will be set or removed.

To remove tags deliberately, erase the field’s content, or check the relevant fields and use Clear Selected. A Remove indicator appears beside those fields. Saving asks for confirmation listing the removals. Cancel preserves the pending changes without writing. Entering a replacement value cancels that field’s removal intent. The same rules apply to Edit ALL Tags (formerly Edit Selected Tags); checking an empty field or choosing Common Fields alone never deletes a tag.

Lyrics uses plain embedded USLT frames in ID3v2.3/v2.4 with a multiline editor. The first nonempty entry is displayed. Updating it preserves the language/description and additional language entries. Unchanged USLT frames are retained byte for byte. Explicitly clearing Lyrics removes all USLT entries for the selected files. Synchronized SYLT lyrics remain untouched; the separate Purge configuration can remove both types. Malformed or protected lyrics are rejected rather than rewritten speculatively. No lyrics are fetched online.

Regression checks cover both real model save paths with seven disposable files, per-file Title/Track preservation, blank and mixed inputs, explicit field removal, Lyrics encodings, alternate entries, synchronized-frame preservation and unchanged audio. Existing prerelease write limitations in the README still apply. This change does not restore tags previously removed from user files.
