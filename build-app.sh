#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$project_dir/Checks/release-check.py"
swift build --package-path "$project_dir" -c release
binary_dir="$(swift build --package-path "$project_dir" -c release --show-bin-path)"
bundle_dir="$(dirname "$project_dir")/TagCraft Music Librarian.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources"
cp "$binary_dir/TagCraft" "$bundle_dir/Contents/MacOS/TagCraft Music Librarian"
cp "$project_dir/Assets/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$project_dir/Assets/AppIcon.icns" "$bundle_dir/Contents/Resources/TagCraftBrand.icns"
cp "$project_dir/Assets/BrandOriginal.png" "$bundle_dir/Contents/Resources/BrandOriginal.png"
codesign --force --sign - "$bundle_dir"
codesign --verify "$bundle_dir"

python3 "$project_dir/Checks/release-check.py" "$bundle_dir"
