# Changelog

## 0.6.3-beta.1

- Target macOS 26.0 and later on Apple silicon.
- Rebuild Tesseract from verified source for macOS 26.0 rather than changing a binary deployment flag.
- Keep dependency auditing and fail builds whose engines require a later macOS version.
- Validate on the development Mac; independent macOS 26.0 runtime validation remains required.

## 0.6.2-beta.1

- Fix protected-folder permission failures by processing temporary copies through the native app.
- Remember selected folder access across actions and launches with security-scoped bookmarks.
- Add a folder-access menu action, bilingual usage descriptions, and permission retry without losing editor settings.
- Keep outputs beside each original, preserve collision handling and completed results, and clean private workspaces.
- Add native staging, bookmark, collision, batch, combined-output, cancellation, and Downloads regression checks.

## 0.6.1-beta.1

- Add native launch-at-login registration with a bilingual menu toggle and macOS approval handling.
- Respect later opt-outs and keep test/preview runs from changing login items.
- Add a minimal, responsive Next.js landing page and repository deployment instructions.

## 0.6.0-beta.1

- Rename the project, app bundle, engine, documentation, and release assets to Anasing.
- Reduce the action bar from 142 to 108 points high and make each option narrower.
- Replace numeric text fields with sliders, steppers, and selectors; add native color pickers and swatches.
- Add photo adjustment previews, original comparison, and reset.
- Add media playback, scrubbing, draggable range handles, and snapshot position chips.
- Add selectable PDF thumbnails, page ordering, and rotation.
- Validate editor choices and check real image, PDF, and trimmed-video output from native controls.

## 0.5.0-beta.1

- Replace the radial wheel with a horizontal glass action bar above the dragged file/folder.
- Increase hover and selection sound levels.
- Preserve English/Arabic labels, latched modifier modes, status cards, output previews, and same-folder results.
- Bundle standalone Python, Office conversion, media conversion, OCR, and their libraries.
- Add portable dependency auditing, conversion tests, DMG packaging, source archives, and a GitHub Actions beta workflow.
- Target Apple silicon Macs running macOS 26.6.2 or later for this bundled beta.
- License Anasing under AGPL-3.0-only.

This beta is ad-hoc signed. Developer ID signing, notarization, and independent clean-Mac validation remain release tasks.
