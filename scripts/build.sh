#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c debug --arch arm64 --arch x86_64
app="$PWD/dist/Nooks.app"
mkdir -p "$app/Contents/MacOS"
cp .build/apple/Products/Debug/Nooks "$app/Contents/MacOS/Nooks"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources" && cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --options runtime --sign "${SIGN_IDENTITY:-Developer ID Application: Chieler Li (2DS36Z35HX)}" --identifier dev.nooks.app "$app"
lipo "$app/Contents/MacOS/Nooks" -verify_arch arm64 x86_64
printf 'Built %s\n' "$app"
