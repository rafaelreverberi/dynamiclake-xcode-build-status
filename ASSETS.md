# Asset provenance

The owner supplied `Xcode__Liquid_Glass__B7GcnoIhKy_icns-a7272c9e5e.icns` on 2026-10-01 and explicitly requested it as the plugin title image and the image behind the **Xcode App Icon** setting. An unchanged copy is retained as `assets/xcode-liquid-glass.icns`.

Source SHA-256: `d609c426a499760f436a4b682ebc16e135f3db9029256381ea1bcd91702c69db`.

`XcodeBuildStatus.dynamiclakeplugin/icon.png` is its 512 × 512 PNG conversion. Transparency, composition and the source’s existing rounded shape are preserved; no additional mask, background or corners are drawn. The conversion does not redesign the supplied image. This owner-requested asset replaces the original workshop illustration and the previous lookup of the locally installed Xcode app icon.

Regenerate on macOS:

```sh
python3 scripts/prepare_icon.py
```

The runtime uses `XcodeBuildStatus.dynamiclakeplugin/xcode-icon.png`, a faithful 128 × 128 downsample of the title PNG, as explicit `inlineData` with PNG MIME type in both activity slots. It is read once into memory from beside the executable. Each image is limited to 15,500 bytes so up to three copies of base64 data fit the documented 64 KB frame limit. The hammer alternative remains an SF Symbol. No app-icon lookup, runtime rendering or downloads are used.

The original artwork’s author, source license and upstream origin were not provided. No ownership or redistribution license is asserted here. Apple and DynamicLake names identify compatibility and do not imply endorsement. No separate asset or source license is granted by this repository. The package has not been submitted to Market.
