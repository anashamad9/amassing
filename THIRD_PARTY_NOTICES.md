# Third-party notices

Anasing source code is licensed under GNU AGPL version 3 only. Bundled components retain their original licenses and copyright notices.

The app contains:

- CPython 3.12.15 via Astral's python-build-standalone 20261013 distribution; PSF and bundled-library licenses are included in the Python installation.
- PyMuPDF 1.26.5 / MuPDF 1.26.10, under AGPL/commercial licensing; this release uses the AGPL option.
- LibreOffice 26.8.1, with its MPL/LGPL/Apache and component notices preserved in the nested app and `Contents/Resources/Licenses/LibreOffice`.
- FFmpeg 9.0.2, configured with GPL/version3 support, and its linked codec libraries. Exact build recipes and copied licenses are under `Contents/Resources/Licenses/homebrew`.
- Tesseract 5.5.3 and English/OSD OCR data, with their component notices.
- Pillow, pillow-heif and its bundled image codecs, python-docx, python-pptx, openpyxl, ebooklib, Beautiful Soup, lxml, pypandoc/Pandoc, rarfile, and their dependencies. License texts are preserved in their Python distribution metadata.

The exact Python package versions are in `requirements-release.lock`. `Contents/Resources/bundle-manifest.json` records engine versions and load-command relocations. `docs/THIRD_PARTY_SOURCES.json` records downloaded source archives, upstream URLs, checksums, and any retrieval failures.

The release assets include the Anasing source archive and a separate third-party source archive with build recipes and upstream source distributions. A publisher must retain access to corresponding sources required by the components' applicable licenses. If source retrieval reports an unavailable component, resolve its source availability before presenting the binary release as complete.

Anasing's original icon and sound effects are generated from the editable SVG and build code in this repository. No proprietary Tangerine or ShelfyDock assets or code are included.
