# Changelog

## 0.1.5 — 2026-10-01

- Remove the settings preview button and use the photo SF Symbol for the Xcode App Icon choice.
- Show plain green checkmark / red xmark SF Symbols for completion in both compact and Sneak Peek slots, without status circles.

## 0.1.4 — 2026-10-01

- Fix the observed generic executable icon by sending the supplied artwork as explicit inline PNG data in both slots.
- Add a Preview Icon button directly below Build Icon; native settings do not support embedded image rows.
- Load the bounded 128 px PNG once relative to the executable, independent of the host working directory.

## 0.1.3 — 2026-10-01

- Use the owner-supplied Liquid Glass Xcode icon as the plugin title image.
- Xcode App Icon selection now uses the same bundled icon through DynamicLake’s native appIcon component.
- Remove local Xcode icon lookup, runtime rendering and duplicate inline image payloads.

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
