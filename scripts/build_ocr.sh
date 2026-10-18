#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# Build the actual OCR executable/library for macOS 26.0; never rewrite deployment load commands.
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$PWD"
TASK_CACHE="$PWD/.release-cache"
mkdir -p "$TASK_CACHE"
if [[ ! -x "$TASK_CACHE/build-tools-venv/bin/cmake" ]]; then
  TASK_PYTHON="${ANASING_BUILD_PYTHON:-python3}"
  if [[ -x "$TASK_CACHE/python-runtime/python/bin/python3" ]]; then TASK_PYTHON="$TASK_CACHE/python-runtime/python/bin/python3"; fi
  "$TASK_PYTHON" -m venv "$TASK_CACHE/build-tools-venv"
  "$TASK_CACHE/build-tools-venv/bin/python3" -m pip install --disable-pip-version-check cmake==4.4.3
fi
TASK_SOURCE="$TASK_CACHE/corresponding-sources/tesseract-5.5.3--5.5.3.tar.gz"
if [[ ! -f "$TASK_SOURCE" ]]; then
  TASK_SOURCE="$TASK_CACHE/tesseract-5.5.3-source.tar.gz"
  if [[ ! -f "$TASK_SOURCE" ]]; then curl -fL 'https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.5.3.tar.gz' -o "$TASK_SOURCE"; fi
fi
TASK_SUM=$(shasum -a 256 "$TASK_SOURCE" | cut -d ' ' -f 1)
[[ "$TASK_SUM" == 9218e62793116d42a9f6d14cd9348518b27f382096eea3d0f2d1a24616bb5884 ]] || { echo 'Tesseract source checksum mismatch'; exit 1; }
if [[ ! -d "$TASK_CACHE/tesseract-5.5.3" ]]; then tar -xzf "$TASK_SOURCE" -C "$TASK_CACHE"; fi
# Homebrew Leptonica ships pkg-config metadata, but no CMake config. Describe those real headers/library to CMake.
mkdir -p "$TASK_CACHE/leptonica-cmake"
python3 - <<'PY'
from pathlib import Path
import re
cache=Path('.release-cache/leptonica-cmake')
prefix=Path('/opt/homebrew/opt/leptonica').resolve()
text=(prefix/'lib/pkgconfig/lept.pc').read_text()
version=re.search(r'^Version: (.+)$',text,re.M).group(1)
(cache/'LeptonicaConfig.cmake').write_text(f'set(Leptonica_FOUND TRUE)\nset(Leptonica_VERSION "{version}")\nset(Leptonica_INCLUDE_DIRS "{prefix}/include/leptonica")\nset(Leptonica_LIBRARIES "{prefix}/lib/libleptonica.dylib")\n')
(cache/'LeptonicaConfigVersion.cmake').write_text(f'set(PACKAGE_VERSION "{version}")\nif(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)\nset(PACKAGE_VERSION_COMPATIBLE FALSE)\nelse()\nset(PACKAGE_VERSION_COMPATIBLE TRUE)\nendif()\n')
PY
export MACOSX_DEPLOYMENT_TARGET=26.0
"$TASK_CACHE/build-tools-venv/bin/cmake" -S "$TASK_CACHE/tesseract-5.5.3" -B "$TASK_CACHE/ocr-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_PREFIX_PATH=/opt/homebrew -DLeptonica_DIR="$TASK_CACHE/leptonica-cmake" \
  -DCMAKE_INSTALL_PREFIX="$TASK_CACHE/ocr-macos26" -DCMAKE_INSTALL_RPATH='@loader_path/../lib' -DBUILD_SHARED_LIBS=ON -DBUILD_TRAINING_TOOLS=OFF \
  -DBUILD_TESTS=OFF -DENABLE_NATIVE=OFF -DGRAPHICS_DISABLED=ON -DDISABLE_ARCHIVE=ON -DDISABLE_CURL=ON
"$TASK_CACHE/build-tools-venv/bin/cmake" --build "$TASK_CACHE/ocr-build" --parallel 6
rm -f "$TASK_CACHE/ocr-macos26/bin/tesseract" "$TASK_CACHE/ocr-macos26/lib/libtesseract.5.5.3.dylib"
"$TASK_CACHE/build-tools-venv/bin/cmake" --install "$TASK_CACHE/ocr-build"

codesign --force --sign - "$TASK_CACHE/ocr-macos26/lib/libtesseract.5.5.3.dylib"
codesign --force --sign - "$TASK_CACHE/ocr-macos26/bin/tesseract"
