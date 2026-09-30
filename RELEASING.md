# Releasing

1. Update `version` in `XcodeBuildStatus.dynamiclakeplugin/plugin.json`, add its section in CHANGELOG and update README download names.
2. Run `python3 -B scripts/build_release.py` on macOS with Xcode Command Line Tools and Python 3. The builder rebuilds both architectures and all tests; never publish an old bundled executable after editing Swift source.
3. In `dist`, run `shasum -a 256 -c Xcode-Build-Status-*.zip.sha256`.
4. Extract the ZIP to a temporary directory. Install it through DynamicLake's normal **Install Local** flow; check its own integrity/trust dialog and test using a disposable Xcode project. See docs/VALIDATION.md for the matrix.
5. Review `git diff` and `git status`. Commit source, tests, documentation and the updated bundled executable. Exclude caches, raw logs, DerivedData and credentials.
6. Push `main` and wait for the macOS validation workflow. Create an annotated `vX.Y.Z` tag pointing at the tested commit.
7. Create the GitHub release with the ZIP and SHA-256 assets from `dist`. Verify the remote tag, download both assets again and verify the downloaded checksum.

The builder uses stable ZIP timestamps and explicit Unix modes. Native binary byte-for-byte reproducibility across compiler versions or checkout paths is not promised. Both Mach-O architectures must have the intended minimum OS version; check with `otool -l` if changing build tooling. The ad-hoc signature is verified but is not notarization.

Do not submit to DynamicLake Market without the owner's explicit request. The current Market open-source requirement would need a separate licensing decision; this repository currently grants no source license.
