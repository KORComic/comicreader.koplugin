#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp}"

WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

mkdir -p "$WORK_DIR/comicreader.koplugin"
cp -r "$SCRIPT_DIR/src" "$WORK_DIR/comicreader.koplugin/src"
cp "$SCRIPT_DIR/LICENSE.md" "$SCRIPT_DIR/version.txt" "$SCRIPT_DIR/CHANGELOG.md" "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/main.lua" "$SCRIPT_DIR/_meta.lua" "$WORK_DIR/comicreader.koplugin/"

mkdir -p "$WORK_DIR/statistics.koplugin"
cp "$SCRIPT_DIR/extra-plugins/statistics.koplugin"/*.lua "$WORK_DIR/statistics.koplugin/"

cd "$WORK_DIR"
zip -r "$OUTPUT_DIR/comicreader.koplugin.zip" comicreader.koplugin statistics.koplugin

ls -lh "$OUTPUT_DIR/comicreader.koplugin.zip"
