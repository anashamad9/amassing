#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ANASING_PACKAGE_APP:-$PWD/dist/portable/Anasing.app}"
FLAVOR="${ANASING_DMG_FLAVOR:-unsigned}"
if [[ "$FLAVOR" == signed ]]; then
  codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"
fi
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print AnasingReleaseVersion' "$APP/Contents/Info.plist")
mkdir -p release
STAGING=$(mktemp -d "$PWD/.release-cache/dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/Anasing.app"
codesign --verify --deep --strict "$STAGING/Anasing.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/LICENSE.txt"
if [[ "$FLAVOR" == unsigned ]]; then cp docs/INSTALL.txt "$STAGING/READ ME FIRST.txt"; else
  printf '%s\n' 'Anasing — drag the app into Applications, then open it once.' 'أناسينغ — اسحب التطبيق إلى Applications ثم افتحه مرة واحدة.' 'Apple silicon · macOS 26.0+' > "$STAGING/READ ME FIRST.txt"
fi
cp THIRD_PARTY_NOTICES.md "$STAGING/THIRD_PARTY_NOTICES.txt"
cp "release/Anasing-$VERSION-source.tar.gz" "$STAGING/"
if [[ -f "release/Anasing-$VERSION-third-party-sources.tar.gz" ]]; then
  # Corresponding sources are a separate release asset to keep the DMG smaller.
  cp docs/SOURCE_ACCESS.txt "$STAGING/SOURCE ACCESS.txt"
fi
NAME="Anasing-$VERSION-arm64-$FLAVOR.dmg"
hdiutil create -volname "Anasing Beta" -srcfolder "$STAGING" -format UDZO -ov "release/$NAME"
hdiutil verify "release/$NAME"
(cd release && shasum -a 256 "$NAME" "Anasing-$VERSION-source.tar.gz" > SHA256SUMS.txt)
if [[ -f "release/Anasing-$VERSION-third-party-sources.tar.gz" ]]; then
 (cd release && shasum -a 256 "Anasing-$VERSION-third-party-sources.tar.gz" >> SHA256SUMS.txt)
fi
printf '%s\n' "$PWD/release/$NAME"
