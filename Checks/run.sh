#!/bin/zsh
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/Checks/release-check.py"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/tagcraft-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc "$project_dir/Sources/TagCraft/Tags.swift" \
  "$project_dir/Sources/TagCraft/Features.swift" \
  "$project_dir/Sources/TagCraft/Magic.swift" \
  "$project_dir/Sources/TagCraft/ReviewTools.swift" \
  "$project_dir/Sources/TagCraft/LibraryScanner.swift" \
  "$project_dir/Sources/TagCraft/Pictures.swift" \
  "$project_dir/Sources/TagCraft/ArtworkImage.swift" \
  "$project_dir/Sources/TagCraft/SQLite.swift" \
  "$project_dir/Sources/TagCraft/LibraryStore.swift" \
  "$project_dir/Sources/TagCraft/LegacyStatisticsMigration.swift" \
  "$project_dir/Sources/TagCraft/StatisticsStorage.swift" \
  "$project_dir/Checks/SQLiteChecks.swift" \
  "$project_dir/Checks/main.swift" -o "$check_dir/check"
"$check_dir/check"
