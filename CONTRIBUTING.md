# Contributing

Build with `scripts/setup.sh` and `scripts/build.sh` on an Apple silicon Mac. Anasing uses SwiftUI/AppKit for the interface and a local Python conversion engine. Keep the app a background utility without a primary window or Dock icon.

Preserve English/Arabic labels, same-folder output behavior, original files, drag cancellation, and visible result/error feedback. Run the relevant native checks and conversion tests after changing those workflows. For portable releases, use the bundled-engine test script and dependency audit; a development build passing tests does not prove it is portable.

Report reproducible bugs through GitHub Issues with the Anasing version, macOS version, file type, and steps. Use synthetic or non-sensitive sample files. Do not upload private documents or credentials.

Contributions are accepted under the project's AGPL-3.0-only license.
