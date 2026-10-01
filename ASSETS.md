# Asset provenance

`XcodeBuildStatus.dynamiclakeplugin/icon.png` is an original geometric workshop hammer and checkmark composition created for this repository. Its editable, deterministic AppKit drawing source is `assets/render_icon.swift`.

- 512 × 512 PNG, opaque square background.
- Blue diagonal handle, pale geometric hammer head and a green completion badge.
- No baked rounded outer corners; DynamicLake applies its own mask.
- No Apple Xcode artwork, application icon or rasterized Apple assets were copied.

Regenerate on macOS with:

```sh
swift assets/render_icon.swift XcodeBuildStatus.dynamiclakeplugin/icon.png
```

The default runtime icon uses DynamicLake's documented `sfSymbol` component with `hammer.fill`; no SF Symbol artwork is bundled. The optional **Xcode App Icon** is read locally using `NSWorkspace.icon(forFile:)` from the running or macOS-registered Xcode installation. It is rendered as a transparent PNG and cached in memory, never written into the package or redistributed. On Xcode 27 this uses its current app icon. Apple retains ownership of that artwork. Inline images are capped at 20,000 bytes so both UI slots fit the documented 64 KB framed JSON budget (also below the 48 KB decoded-image limit). Apple and DynamicLake names identify compatibility and do not imply endorsement. This file grants no separate asset or source license.
