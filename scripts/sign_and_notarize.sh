#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANASING_SIGN_IDENTITY:?Set your Developer ID Application signing identity}"
: "${ANASING_NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
APP="$PWD/dist/signed/Anasing.app"
mkdir -p dist/signed .release-cache release
rsync -a --delete dist/portable/Anasing.app/ "$APP/"
export ANASING_SIGN_APP="$APP"
python3 - <<'PY'
import os,subprocess
from pathlib import Path
app=Path(os.environ['ANASING_SIGN_APP']);identity=os.environ['ANASING_SIGN_IDENTITY']
magic={b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf'}
def sign(path):subprocess.run(['/usr/bin/codesign','--force','--options','runtime','--timestamp','--sign',identity,str(path)],check=True)
for p in sorted(app.rglob('*'),key=lambda p:len(p.parts),reverse=True):
 if p.is_symlink():continue
 if p.is_file():
  with p.open('rb') as f:kind=f.read(4)
  if kind in magic:sign(p)
 elif p.suffix in {'.app','.framework','.xpc','.bundle'}:
  if (p/'Contents/Info.plist').exists() or (p/'Resources/Info.plist').exists():sign(p)
sign(app)
PY
codesign --verify --deep --strict "$APP"
ANASING_TEST_APP="$APP" ./scripts/test_portable.sh
ZIP="$PWD/.release-cache/Anasing-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$ANASING_NOTARY_PROFILE" --wait --output-format json > .release-cache/notary-app.json
python3 - <<'CHECK_APP'
import json
result=json.load(open('.release-cache/notary-app.json'))
if result.get('status')!='Accepted': raise SystemExit('Notarization was not accepted: '+str(result))
CHECK_APP
xcrun stapler staple "$APP"
ANASING_PACKAGE_APP="$APP" ANASING_DMG_FLAVOR=signed ./scripts/package_dmg.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print AnasingReleaseVersion' "$APP/Contents/Info.plist")
DMG="$PWD/release/Anasing-$VERSION-arm64-signed.dmg"
codesign --force --timestamp --sign "$ANASING_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$ANASING_NOTARY_PROFILE" --wait --output-format json > .release-cache/notary-dmg.json
python3 - <<'CHECK_DMG'
import json
result=json.load(open('.release-cache/notary-dmg.json'))
if result.get('status')!='Accepted': raise SystemExit('DMG notarization was not accepted: '+str(result))
CHECK_DMG
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
(cd release && shasum -a 256 *.dmg *source.tar.gz > SHA256SUMS.txt)
