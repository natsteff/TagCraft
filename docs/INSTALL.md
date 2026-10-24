# Installing TagCraft on macOS

See [the README installation instructions](../README.md#installation) for the current steps and Apple’s official guidance for an unnotarized app.

## Instructions to include inside future disk images

Copy TagCraft Music Librarian.app into /Applications using Finder.

In the opened TagCraft disk image, drag the app onto the Applications shortcut in that same Finder window. The Dock’s Apps launcher is not the install destination.

Alternatively: select the app, press Command-C, press Command-Shift-G in Finder, enter /Applications, press Return, then press Command-V. No sidebar favorite is required. Wait for the copy to finish, eject the disk image, and open the app from Finder → Go → Applications.

For updates: quit TagCraft with Command-Q, open the newer DMG, drag its app onto the Applications shortcut in that window, choose Replace when Finder asks, wait for copying, eject the DMG, and reopen TagCraft from Finder → Go → Applications. Verify the version/build under Settings → About TagCraft. Settings and statistics data remain separate and should not be deleted. Follow Apple's instructions if macOS blocks opening the app:
https://support.apple.com/en-us/102445

The beta is not notarized. Use disposable copies with independent backups for music-file edits and moves; see the README safety notice.

## Packaging requirement

Future DMGs must include the app and a working Applications shortcut side by side, plus installation text based on the instructions above. The 0.7.0 Beta Build 1 disk image contains the app, an Applications shortcut and INSTALL.txt generated from bundle metadata. The older published 0.6.0 Alpha Build 1 image also contains an Applications shortcut. App versions in packaged instructions must be generated from the bundle metadata, not copied from an old release.
