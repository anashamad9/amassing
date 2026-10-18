#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build-cache/clang"
mkdir -p .build/release
swiftc -O -target arm64-apple-macosx14.0 -parse-as-library -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/Anasing/*.swift -o .build/release/Anasing
APP="$PWD/dist/Anasing.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Anasing "$APP/Contents/MacOS/Anasing"
cp Info.plist "$APP/Contents/Info.plist"
if [[ ! -f assets/Anasing.icns || assets/Anasing.svg -nt assets/Anasing.icns ]]; then .venv/bin/python3 scripts/make_icon.py; fi
cp assets/Anasing.icns "$APP/Contents/Resources/Anasing.icns"
mkdir -p "$APP/Contents/Resources/engine"
cp engine/anasing_engine.py "$APP/Contents/Resources/engine/"
mkdir -p "$APP/Contents/Resources/sounds"
cp assets/sounds/*.wav "$APP/Contents/Resources/sounds/"
if [[ -x .venv/bin/python3 ]]; then
  mkdir -p "$APP/Contents/Resources/runtime/lib"
  rm -rf "$APP/Contents/Resources/runtime/bin"
  rsync -a --exclude=__pycache__ .venv/lib/ "$APP/Contents/Resources/runtime/lib/"
fi
codesign --force --sign - "$APP"
echo "Built $APP"
