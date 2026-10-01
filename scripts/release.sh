#!/bin/bash
# Release build: universal, Developer ID signed, notarized, stapled, packaged as a dmg.
# One-time setup: xcrun notarytool store-credentials nooks-notary --apple-id <id> --team-id 2DS36Z35HX
set -euo pipefail
cd "$(dirname "$0")/.."
identity="${SIGN_IDENTITY:-Developer ID Application: Chieler Li (2DS36Z35HX)}"
profile="${NOTARY_PROFILE:-nooks-notary}"
swift build -c release --arch arm64 --arch x86_64
app="$PWD/dist/Nooks.app"
rm -rf "$app" dist/Nooks.zip dist/Nooks.dmg dist/dmg
mkdir -p "$app/Contents/MacOS"
cp .build/apple/Products/Release/Nooks "$app/Contents/MacOS/Nooks"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources" && cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app"
# Notarize and staple the app first so the copy inside the dmg works offline.
ditto -c -k --keepParent "$app" dist/Nooks.zip
xcrun notarytool submit dist/Nooks.zip --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
rm dist/Nooks.zip
mkdir dist/dmg && cp -R "$app" dist/dmg/ && ln -s /Applications dist/dmg/Applications
hdiutil create -volname Nooks -srcfolder dist/dmg -ov -format UDZO dist/Nooks.dmg
rm -rf dist/dmg
codesign --force --timestamp --sign "$identity" dist/Nooks.dmg
xcrun notarytool submit dist/Nooks.dmg --keychain-profile "$profile" --wait
xcrun stapler staple dist/Nooks.dmg
spctl --assess --type execute --verbose "$app"
spctl --assess --type open --context context:primary-signature --verbose dist/Nooks.dmg
printf 'Ready: %s\n' dist/Nooks.dmg
