# Changelog

## 0.1.2 — 2026-10-01

- Restore automatic failure dismissal after the selected duration.
- Add a live Build Icon selector: existing hammer SF Symbol or the official icon from the local Xcode installation, including Xcode 27.
- Cache locally rendered transparent icons in memory; preserve proportions and bound duplicate inline images to the frame budget.

## 0.1.1 — 2026-10-01

- Keep failed build status and diagnostic available on hover until the next build or lifecycle cleanup.
- Failure duration now controls only automatic Sneak Peek presentation; success dismissal is unchanged.
- Retained failures have no dismissal timer or repeating idle updates.

## 0.1.0 — 2026-09-30

- Initial native Swift JSON plugin with event-driven Xcode GUI build observation.
- Blue SF Symbol hammer, native indeterminate/estimated progress and success/failure status.
- Feature-detected completion Sneak Peek and two dynamically read duration sliders.
- Local bounded EWMA duration history, stale/duplicate filtering and cancellation cleanup.
- Bounded SLF 13 diagnostic/cancellation reader, tested against Xcode 27 logs.
- Universal Apple Silicon/Intel package, automated tests, validation, ZIP and SHA-256 tooling.
