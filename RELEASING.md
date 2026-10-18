# Publishing Anasing on GitHub

The prepared **0.6.1-beta.1** bundle is self-contained for **Apple silicon, macOS 26.6.2+**. It is a development beta with an ad-hoc signature. It is **not** Apple-notarized. No Developer ID signing identity was installed on the machine that prepared this package.

## Files to upload

Use GitHub's **Releases → Draft a new release**, tag `v0.6.1-beta.1`, and mark it **Pre-release**. Attach the files from `release/`:

- `Anasing-0.6.1-beta.1-arm64-unsigned.dmg`
- `Anasing-0.6.1-beta.1-source.tar.gz`
- `Anasing-0.6.1-beta.1-third-party-sources.tar.gz`
- `SHA256SUMS.txt`

Also attach the generated portable audit and test report if desired. Explain clearly that the binary is an **unsigned beta** that macOS may block. A public source repository and a test DMG are prepared; a smooth, normal public installation experience still requires Developer ID signing and notarization.

Do **not** put DMGs, `.app` bundles, runtimes, caches, or source-dependency archives in Git commits. `.gitignore` excludes them. Binary and corresponding-source archives are Release assets. Publish the source assets together with the binary and keep the required source materials available under their component licenses.

## Push the repository

The GitHub repository is [anashamad9/amassing](https://github.com/anashamad9/amassing). For a fresh clone, run these commands in the project directory:

```sh
git clone https://github.com/anashamad9/amassing.git
cd amassing
```

Then draft the release and upload the assets using GitHub's web interface. The `Build beta` workflow can also regenerate unsigned assets with **Actions → Build beta → Run workflow**, or from a pushed `v*` tag. It creates downloadable workflow artifacts; it does not publish a release automatically.

## Build the same artifact locally

```sh
./scripts/setup.sh
./scripts/fetch_runtime.sh
./scripts/build.sh
python3 scripts/bundle_portable.py
./scripts/test_portable.sh
python3 scripts/collect_sources.py
python3 scripts/create_source_archive.py
./scripts/package_dmg.sh
```

The source collector checks upstream checksums where supplied and records retrieval results in `docs/THIRD_PARTY_SOURCES.json`. Resolve unavailable-source entries before presenting source materials as complete. The app includes the original third-party license texts and Homebrew build recipes. Build dependencies are pinned in `requirements-release.lock`; the standalone Python archive is checksum-verified. Homebrew engine versions and relocations are recorded in the bundled manifest.

## Developer ID signing and notarization

To ship a regular public installer, the publisher needs an Apple Developer Program account, a **Developer ID Application** certificate with its private key installed in Keychain, and a configured `notarytool` Keychain profile. Do not put certificates, passwords, private keys, or profiles in the repository.

The helper script prepares a signed copy, signs nested code from the inside out, tests it, submits it to Apple's notary service, staples accepted tickets, and builds the signed DMG:

```sh
export ANASING_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export ANASING_NOTARY_PROFILE='your-existing-keychain-profile'
./scripts/sign_and_notarize.sh
```

The signing path is prepared but cannot be exercised without your certificate/profile. Inspect notarization results and test the downloaded, quarantined DMG on a clean Mac before publication. Do not disable Gatekeeper or remove quarantine to make a failing release appear valid.

Apple documentation: [packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [universal binaries](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).

## Release checks

- Confirm declared minimum macOS is at least the maximum required by the packaged code.
- Use the bundled-engine test script and verify the sealed bundle remains valid after tests.
- Mount and verify the DMG, copy the app to a separate path, and test it there.
- Validate on a clean Apple silicon Mac without Homebrew, Xcode, Python, or LibreOffice.
- Check source assets, notices, version numbers, checksums, and signing/notarization state.

For broader macOS or Intel support, rebuild and test all bundled engines for those targets. Changing only `LSMinimumSystemVersion` or compiling an Intel Swift executable is insufficient.
