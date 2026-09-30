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

The runtime uses DynamicLake's documented `sfSymbol` image component with `hammer.fill`; no SF Symbol artwork is bundled in the package. Apple and DynamicLake names identify compatibility and do not imply endorsement. This file grants no separate asset or source license.
