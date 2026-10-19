# TagCraft brand assets

`BrandOriginal.png` is the full-resolution, unmodified TagCraft Music Librarian logo supplied by the project owner. Preserve it as the master source for future branding work. It contains the waveform/TC symbol, TagCraft wordmark and MUSIC LIBRARIAN subtitle. The project README displays this file through a repository-relative link suitable for GitHub.

The app bundles this master and crops the required portions during rendering. Small subtitles are drawn as native text at their final display size; avoid enlarging a previously rendered logo view, which can blur text. Keep the source uncropped so future layouts can reuse the complete design.

`AppIcon.png` and `AppIcon.icns` are the derived application icons, omitting the subtitle. `BrandWordmark.png` is an older derived asset; current runtime branding uses `BrandOriginal.png`.

The build script copies the required runtime assets into the application bundle. No branding file depends on the original Downloads location.
