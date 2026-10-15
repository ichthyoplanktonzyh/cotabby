# Lingrove brand assets

`lingrove-logo.svg` is the approved production master. Keep its SVG source exact; the PNG files in
the Xcode catalog and GitHub README are generated renditions of that master.

## Generated assets

Run `scripts/generate_brand_assets.mjs` to refresh the catalog outputs. The script produces the
128/256/384-pixel `LingroveLogo` image set, the 18/36/54-pixel `MenuBarWhaleIcon` template set,
standard macOS `AppIcon` and `AppIconDev` representations from 16 through 1024 pixels, and the
512-pixel GitHub README logo. Every image has a transparent background.

The menu-bar version is made from the master paths: navy regions become white in a luminance mask,
while turquoise and white regions become black. The generated mask trims only the master's empty
outer margin, preserving the entire whale silhouette while making better use of the 18-pixel slot.
The PNG stores the silhouette as black with transparency outside it, and the asset catalog marks it
as a template. Lingrove uses the alpha-only template so macOS/SwiftUI supplies the foreground tint
that follows the current appearance. The development app icon adds a small amber `DEV` capsule in
empty space above the whale. Its letterforms are vector paths, and the source whale remains unchanged
beneath that separate overlay.

## Activation indicator

`lingrove-activation-indicator.svg` is the exact supplied activation symbol and remains a separate
master from the full-whale brand mark. The generator creates the 14/28/42-pixel
`ActivationIndicatorWhaleTail` image set from a working optical-size derivative; the master file is
never rewritten. For each scale, the generator sets the SVG root to the target pixel dimensions and
renders directly, adds a round-joined 10-unit stroke to all three source paths, and expands the
viewBox by 5 source units on each side (`-5 -5 405 405`) so the frame stays unclipped. The rounded
frame is about 25 source units thick in the derivative, or `25 × 14 / 405 ≈ 0.86 pt` at 1x. The
renderer keeps the derivative's antialiased alpha in black RGBA pixels; SwiftUI/macOS applies the
template foreground tint for the current appearance. All three source paths remain present.

Sharp is a build-time tool only; it is not an app or repository dependency. If `sharp` is already
available to Node's normal module resolver, run:

```sh
node scripts/generate_brand_assets.mjs
```

To install it into the ignored `build/` directory when needed, then pass that module explicitly:

```sh
npm install --prefix build/branding-tools --no-save --package-lock=false sharp@0.35.5
node scripts/generate_brand_assets.mjs --sharp-module "$PWD/build/branding-tools/node_modules/sharp"
```

The optional `--sharp-module PATH` accepts either the Sharp package directory or its entry point.
