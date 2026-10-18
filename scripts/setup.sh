#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -x .release-cache/python-runtime/python/bin/python3 ]]; then
  .release-cache/python-runtime/python/bin/python3 -m venv .venv
else
  python3 -m venv .venv
fi
.venv/bin/python3 -m pip install --disable-pip-version-check -r requirements.txt
if [[ ! -x /opt/homebrew/bin/ffmpeg || ! -x /opt/homebrew/bin/tesseract ]]; then
  /opt/homebrew/bin/brew install ffmpeg tesseract
fi
if [[ ! -x /Applications/LibreOffice.app/Contents/MacOS/soffice ]]; then
  /opt/homebrew/bin/brew install --cask libreoffice
fi
echo "Anasing conversion engines are ready."
