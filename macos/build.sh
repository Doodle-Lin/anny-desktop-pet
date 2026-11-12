#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
TEMP_BUILD="$(mktemp -d)"
trap 'rm -rf "$TEMP_BUILD"' EXIT
APP="$TEMP_BUILD/Anny.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "${ARCH}-apple-macos11.0" -framework AppKit "$ROOT/macos/main.swift" -o "$TEMP_BUILD/Anny-$ARCH"
done
lipo -create "$TEMP_BUILD/Anny-arm64" "$TEMP_BUILD/Anny-x86_64" -output "$APP/Contents/MacOS/Anny"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/assets" "$APP/Contents/Resources/assets"
codesign --force --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/Anny"
# Build into a fresh temporary app before replacing individual output files.
ditto "$APP" "$OUT/Anny.app"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/AnnyDesktop-v4.1.0-macos-universal.zip"
printf 'Built: %s\n' "$OUT/AnnyDesktop-v4.1.0-macos-universal.zip"
