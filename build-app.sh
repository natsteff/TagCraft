#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$project_dir/scripts/generate-terms.py"
python3 "$project_dir/Checks/release-check.py"
swift build --package-path "$project_dir" -c release
binary_dir="$(swift build --package-path "$project_dir" -c release --show-bin-path)"
bundle_dir="$project_dir/outputs/TagCraft Music Librarian.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
# Replace files atomically so an already-running executable is not truncated.
stage_copy() {
    local staged_file="$2.update.$$"
    cp "$1" "$staged_file"
    mv -f "$staged_file" "$2"
}
stage_copy "$binary_dir/TagCraft" "$bundle_dir/Contents/MacOS/TagCraft Music Librarian"
stage_copy "$project_dir/Assets/Info.plist" "$bundle_dir/Contents/Info.plist"
stage_copy "$project_dir/Assets/AppIcon.icns" "$bundle_dir/Contents/Resources/TagCraftBrand.icns"
stage_copy "$project_dir/Assets/BrandOriginal.png" "$bundle_dir/Contents/Resources/BrandOriginal.png"
stage_copy "$project_dir/LICENSE" "$bundle_dir/Contents/Resources/LICENSE"
stage_copy "$project_dir/USAGE-NOTICE.md" "$bundle_dir/Contents/Resources/USAGE-NOTICE.md"
rm -f "$bundle_dir/Contents/Resources/EULA.md"
mkdir -p "$bundle_dir/Contents/Resources/Legal"
stage_copy "$project_dir/Legal/CORE-TERMS.txt" "$bundle_dir/Contents/Resources/Legal/CORE-TERMS.txt"
stage_copy "$project_dir/Legal/TAGCRAFT-NOTES.txt" "$bundle_dir/Contents/Resources/Legal/TAGCRAFT-NOTES.txt"
codesign --force --sign - "$bundle_dir"
codesign --verify --strict "$bundle_dir"
touch "$bundle_dir"

python3 "$project_dir/Checks/release-check.py" "$bundle_dir"
