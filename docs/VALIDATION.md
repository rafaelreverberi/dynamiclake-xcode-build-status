# 0.1.2 validation scope

Version 0.1.2 restores timed failure dismissal and adds the live Build Icon selector. The icon is obtained from the installed Xcode app without redistributing Apple artwork. Regression tests cover failure deadlines, icon settings/fallback, native rendering/transparency, inline-image/frame limits and the installed Xcode icon when available. Local validation passed **28 Swift tests and 6 Python tests**, universal build/package checks and ZIP checksum verification. The local Xcode 27 app icon rendered to a 128 px PNG of **18,606 bytes**, within the duplicate-slot frame budget. This update is packaged for owner installation; the installed 0.1.1 package is intentionally untouched. Visual icon selection and real-host timing after installation still require user confirmation.

# 0.1.1 validation scope

The 0.1.0 observations below remain historical evidence. Version 0.1.1 intentionally changes failure dismissal: failure duration controls automatic presentation only, while the failed activity and its diagnostic remain available on hover until replaced or lifecycle cleanup. Regression tests cover retention, absence of a failure dismissal deadline and replacement by a new build. All 24 Swift tests and 5 Python tests passed locally, and the universal release archive passed package validation. The 0.1.1 update was installed through DynamicLake’s normal update dialog; installed manifest, icon and executable hashes match the release package. Native hover rendering still requires visual confirmation.

# Validation record

Local validation on 2026-09-30, Apple Silicon macOS 27, Xcode **27.0 (27A266a)**, DynamicLake Pro **1.9.7.5**. Evidence is separated below; a socket payload is not proof of on-screen rendering.

## Automated checks

- **22 Swift tests**: 19 pure core tests and 3 native runtime tests, zero failures.
- **5 Python package-validation tests**, zero failures.
- Release builder passed: both architectures, ad-hoc signature verification, executable bit, exact two sliders, manifest/changelog/icon/package limits, archive integrity and top-level structure.
- ZIP checksum verified locally. Both Mach-O slices declare macOS 13 minimum deployment.

Native runtime tests exercise kqueue settings changes in temporary directories, including atomic replacement and in-place writes; journal replacement identity, symlink rejection and bounded file reading. No test requires an active Xcode build.

## Real Xcode + controlled local socket

A disposable command-line Swift Xcode project was created outside the repository. Its test-only shell phase waited eight seconds to make the observation window measurable. No important project was changed. Xcode's own scripting `build`/`stop` commands triggered the GUI build engine; there was no System Events automation, toolbar scraping, Accessibility observation or UI-based build detection. The plugin runtime remained independent of these test commands.

Observed:

- Initial build: native indeterminate progress message followed by actual success.
- Repeated comparable build: elapsed-time EWMA progress updates, capped at 0.95.
- Intentional compiler failure: actual failed status and `Cannot find 'missingBuildProbeValue' in scope`.
- Cancellation: journal disappearance, SLF cancellation flag and dismissal; no false success/failure.
- Success/failure duration settings 2 and 3 seconds: dismissal after approximately **2.02 / 3.02 seconds**.
- A second build while the first completion was visible: active state took precedence.
- Restart midway through a real build: live writer lock enabled adoption, indeterminate progress and correct final success.
- Atomic live setting change from 10 to 1 second during completion: dismissal after **1.024 seconds from the original completion**, with no timer restart.
- Old manifests on startup: dismiss-only cleanup, no stale create.
- No raw paths/source/whole logs in captured socket frames; frames used hammer SF Symbol, native progress/status and feature-gated completion Sneak Peek.

## Idle resource observation

After a real build and dismissal, a debug native process connected to the controlled local Unix socket was sampled twice over **30 seconds** using `ps -p PID -o %cpu,rss,time`:

| Metric | Before | After |
| --- | --- | --- |
| CPU shown by ps | 0.0% | 0.0% |
| RSS | 12,960 KiB (12.66 MiB) | 12,960 KiB |
| Accumulated CPU time | 0:00.02 | 0:00.02 |
| Additional socket frames | — | 0 |

This is a measured short idle observation on one machine with a small DerivedData set, not a promise of literally zero CPU or a large-project benchmark. Release/runtime-host RSS can differ. The design has no repeating timer when all activities are dismissed.

## DynamicLake host validation

The final local package was installed through DynamicLake's normal installation handling. The app's Plugin Status showed **Xcode Build Status — Running 0.1.0**. Installed manifest, icon and executable hashes were compared to the release package. This confirms actual installation/running state; the controlled socket tests above provide detailed lifecycle/message timing evidence.

## Remaining manual matrix

- Visually confirm hammer size, native circular progress, green/red status and completion Sneak Peek in both notch and pill layouts.
- Exercise both sliders through DynamicLake's native settings window and verify automatic Sneak Peek duration with a competing normal-priority activity.
- Press actual ⌘B / ⌘R and perform Archive in representative app projects and destinations. The automated development build trigger used Xcode's native scripting build command.
- Exercise simultaneous projects, global custom DerivedData location changes, DynamicLake quit/relaunch and the two-hour safety ceiling.
- Run on an Intel Mac and any additional Xcode/log version before claiming that compatibility.

No DynamicLake Market acceptance, notarization or universal compatibility claim is made.
