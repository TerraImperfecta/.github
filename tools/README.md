# Profile assets

`profile/assets/` is generated. Change the generator, not the files.

```bash
swift tools/generate-profile-assets.swift
```

| Output | What it is |
| --- | --- |
| `banner-{light,reversed}.{svg,png}` | 2560 × 640 profile banner. The README shows the PNG. |
| `icon-{light,reversed}.svg` | The mark alone, transparent, shown under the banner |
| `icon-{light,reversed}-512.png` | The same, rasterised, for places that flatten SVG |

`light` is for GitHub's light theme, `reversed` for dark. The README's
`<picture>` blocks switch between them.

## Requirements

- **Swift 6.4**, the version on this Mac and on GitHub's `ubuntu-24.04`. The
  generator is plain Swift and Foundation, with no packages. CI pins
  `ubuntu-24.04` rather than `ubuntu-latest`, because the 26.04 image that
  `ubuntu-latest` is moving to doesn't include Swift.
- **`resvg` 0.48.1** on `PATH`, for the PNGs: `cargo install resvg --version
  0.48.1 --locked`. CI downloads the same version's release binary. Keep them in
  step, because a different renderer version can change the PNGs' bytes.

## Where the geometry comes from

`kit/` holds two files copied **unmodified** from `TerraImperfecta-brand-kit`:

| File | Kit path | Used for |
| --- | --- | --- |
| `even-void.svg` | `01-mark/` | the mark's nine arcs and core |
| `x-header-1500x500.svg` | `07-banner-x/` | the outlined wordmark and tagline, and the lockup's proportions |

The generator reads everything from these files and draws nothing by hand. To
pick up a change to the kit, copy the new file over and regenerate. If the kit's
structure changes in a way the generator doesn't recognise, it stops with an
error rather than guessing.

## Brand rules the generator keeps

From the kit's README:

- **Colour appears in exactly one place: the core of the mark.** That means
  Landfall on light and Ember on dark, never both. The faded mark on the right
  of the banner has an ink-coloured core, as in the kit's own banners.
- **No animation and no colour cycling.** Shells rotating at different speeds
  would eventually line their gaps up and cut a spoke through the mark, which
  the kit forbids. A colour cycle would show both accents.
