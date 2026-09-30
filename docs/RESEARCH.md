# Research and compatibility record

Reviewed on 2026-09-30 before implementation.

## DynamicLake

The current **HTML pages** were fetched over HTTPS from the official documentation site. Its DocC JSON endpoints were older and lacked newer feature fields; HTML was used as the authority for shipping behavior.

- [DynamicLakeKit overview](https://docs.dynamiclake.com/documentation/dynamiclakekit/)
- [Create Your First Plugin](https://docs.dynamiclake.com/documentation/dynamiclakekit/createyourfirstplugin/)
- [JSON Plugin API](https://docs.dynamiclake.com/documentation/dynamiclakekit/jsonpluginapi/)
- [Plugin Packaging and Market](https://docs.dynamiclake.com/documentation/dynamiclakekit/pluginpackagingandmarket/)
- [Design Guidelines](https://docs.dynamiclake.com/documentation/dynamiclakekit/designguidelines/)
- [Live Activities](https://docs.dynamiclake.com/documentation/dynamiclakekit/liveactivities/)
- [Sneak Peeks](https://docs.dynamiclake.com/documentation/dynamiclakekit/sneakpeeks/)

Applied: `.dynamiclakeplugin` top-level package, manifest schema 1, relative executable/icon paths, autoStart, native slider settings, environment-provided socket/settings/features, four-byte big-endian frames, documented image/progress/status/text components, small size and normal priority. `presentSneakPeek` is a numeric duration of 1–10 seconds and is feature-gated. No undocumented component fields or extra surfaces are sent.

Limits used by the builder: archive 7 MB, extracted package 20 MB, manifest 128 KB, PNG icon 1.5 MB. Runtime frames stay below 64 KB; no inline images are used. A square 512-pixel PNG with no baked outer corner radius is bundled. Current Market documentation requires open source; no Market submission is made and no license was invented for this public repository.

## Reference repository

[rafaelreverberi/dynamiclake-ai-agents-plugin](https://github.com/rafaelreverberi/dynamiclake-ai-agents-plugin) was cloned and reviewed: repository/package layout, manifest/settings, executable permissions, framed socket send/receive, settings reloading, state cleanup, tests, release builder/ZIP validation/checksums, workflow, README, changelog, release/security/asset notes and licensing posture. This implementation is independent Swift code. No agent-specific logic, assets or identifiers were copied.

## Xcode and macOS

- [Apple build-system documentation](https://developer.apple.com/documentation/xcode/build-system)
- [Swift Build](https://github.com/swiftlang/swift-build): a build service used by Xcode, SwiftPM and Swift Playground. Its development hooks run modified services; they are not a passive public subscriber API for another client's GUI builds. No service interception or substitution is used.
- Installed Xcode 27 `Contents/Resources/Xcode.sdef`: native scheme `build`/`stop` commands and scheme action results. Used **only to trigger controlled development test builds**, without System Events, keystrokes, UI reading or Accessibility. No AppleScript exists in the shipping runtime.
- [Apple FSEvents guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html): event stream observation, coalescing/overflow and rediscovery considerations.
- [SQLite locking and rollback journals](https://www.sqlite.org/lockingv3.html), [lock-byte definitions](https://github.com/sqlite/sqlite/blob/master/src/os.h): read-only lock inspection distinguishes a live writer from an abandoned journal. The plugin never opens a SQLite connection, takes a database lock or changes the build database.
- [XCLogParser](https://github.com/MobileNativeFoundation/XCLogParser), [SLF format notes](https://github.com/MobileNativeFoundation/XCLogParser/blob/master/docs/Xcactivitylog%20Format.md): studied for format understanding. No dependency or source code is vendored. The small independent reader only extracts diagnostic titles and the verified root trailer fields, with hard bounds and fail-closed parsing.

Observed on local Xcode 27 builds: `build.db-journal` appears early and remains through compilation; the build database reserved lock is held by the build service. The cached request distinguishes normal GUI vs command-line override requests. Logs and manifest entries arrive after completion. `primaryObservable` includes high-level status and error counts. A cancelled GUI build had zero errors and status `W`, but its SLF 13 root cancellation flag was set. A compile failure had a nonzero root result flag while cancellation stayed false. The reader explicitly distinguishes these two flags; it does not use localized “Build succeeded/failed/stopped” strings to classify outcomes.

This compatibility evidence supports a practical filesystem fallback, **not a guarantee of stable Xcode internal formats**. Exact live percentage was not found through a supported passive interface. The UI therefore uses indeterminate progress and bounded historical estimates. Earlier/future SLF versions and different journaling layouts require new fixtures and validation before support is claimed.
