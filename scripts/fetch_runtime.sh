#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .release-cache
ARCHIVE=.release-cache/python-arm64.tar.gz
URL='https://github.com/astral-sh/python-build-standalone/releases/download/20261013/cpython-3.12.15%2B20261013-aarch64-apple-darwin-install_only.tar.gz'
if [[ ! -f "$ARCHIVE" ]]; then curl --fail --location "$URL" -o "$ARCHIVE"; fi
python3 - <<'PY'
from pathlib import Path
import hashlib,tarfile
archive=Path('.release-cache/python-arm64.tar.gz')
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='ba32036ad8f4c434d97a1ee7feef8b7edc0fac16777639b97e39c74a108e4440','Runtime checksum mismatch'
if not Path('.release-cache/python-runtime/python/bin/python3').exists():
 with tarfile.open(archive) as t:t.extractall('.release-cache/python-runtime')
PY
.release-cache/python-runtime/python/bin/python3 -m pip install --disable-pip-version-check -r requirements-release.lock
