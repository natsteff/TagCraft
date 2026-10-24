#!/bin/zsh
set -eu
cd "${0:A:h}/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/tagcraft-ui-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc -D TAGCRAFT_UI_CHECKS -parse-as-library -target "$(uname -m)-apple-macosx14.0" Sources/TagCraft/*.swift Checks/UIModelChecks.swift -o "$check_dir/check"
"$check_dir/check"
