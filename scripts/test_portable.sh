#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ANASING_TEST_APP:-$PWD/dist/portable/Anasing.app}"
mkdir -p artifacts
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Anasing" --smoke-test
"$APP/Contents/MacOS/Anasing" --editor-test
"$APP/Contents/MacOS/Anasing" --pipeline-test
"$APP/Contents/MacOS/Anasing" --pdf-feedback-test
ANASING_BUNDLE_RESOURCES="$APP/Contents/Resources" PATH=/usr/bin:/bin \
 "$APP/Contents/Resources/python/bin/python3" -B -I -W ignore::ResourceWarning -m unittest discover -s tests -v
# Running the app/tests must not alter the sealed bundle.
codesign --verify --deep --strict "$APP"
python3 scripts/audit_release.py --app "$APP" --output artifacts/portable-audit.json
