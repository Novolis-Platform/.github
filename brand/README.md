# Novolis Brand Assets

The primary Novolis logo asset is [`logo-brand-transparent.svg`](logo-brand-transparent.svg).

It is a transparent, vector-only SVG: the mark is built from filled paths with gradients, and the wordmark/tagline are SVG text. The PNG reference remains useful for visual comparison and overlay feedback, but it is not embedded in the primary SVG.

## Single-file library prototype

[`generate-pixel-outlines.cs`](generate-pixel-outlines.cs) is both the generator and a proof-of-concept for a future `novolis-svg` / `novolis-imaging` repository. Everything lives in one file, organized into library-like sections:

| Section | Types | Purpose |
| --- | --- | --- |
| **App** | `BrandLogoApp`, `BrandAssetVerifier` | CLI dispatch, output paths, regression checks |
| **SVG core** | `Vec`, `VectorPath`, `SvgShape`, `SvgDocument`, `SvgXml`, `SvgOverlay` | Path DSL, document builder, gradients, overlays |
| **Brand model** | `NovolisLogoMark`, `NovolisBrandCanvas`, `NovolisBrandGradients`, `NovolisBrandTypography` | Canonical Novolis geometry and styling |
| **Asset recipes** | `BrandAssetRecipes` | Compose full lockup, mark-only, overlay, per-shape, icon, and social outputs |
| **Image bridge** | `SvgRasterBridge` | Optional SVG→PNG via `npx @resvg/resvg-js-cli` (adapter boundary, not baked into SVG core) |

### Canonical shape names

The mark uses exactly six named shapes:

- `upper`
- `lower`
- `n` (merged diagonal + left + right swirls)
- `n_left`
- `n_right`
- `star`

Overlay control points are labeled `<shape>:<number>` (for example `n:1`, `star:4`).

### Future extraction template

When this API feels stable, extract into separate packages/repos:

- **`novolis-svg`** — generic `Vec`, `VectorPath`, `SvgDocument`, gradients, text, overlays (no Novolis coordinates).
- **`novolis-imaging`** — `SvgRasterBridge` and raster export presets.
- **Brand app** — keeps `NovolisLogoMark` and `BrandAssetRecipes` as the Novolis-specific layer.

## Regenerating

Run from this directory:

```powershell
# All SVG variants (default)
dotnet run generate-pixel-outlines.cs -- all

# Individual targets
dotnet run generate-pixel-outlines.cs -- full
dotnet run generate-pixel-outlines.cs -- overlay
dotnet run generate-pixel-outlines.cs -- mark
dotnet run generate-pixel-outlines.cs -- shapes
dotnet run generate-pixel-outlines.cs -- icon
dotnet run generate-pixel-outlines.cs -- social

# SVG + PNG via resvg (requires Node/npx)
dotnet run generate-pixel-outlines.cs -- png

# Regression checks (shape names, overlay labels, mark-only has no wordmark)
dotnet run generate-pixel-outlines.cs -- verify
```

Legacy positional args still work for the full lockup + overlay pair:

```powershell
dotnet run generate-pixel-outlines.cs -- logo-brand-transparent.png logo-brand-transparent.svg 16
```

## Generated outputs

| Output | Description |
| --- | --- |
| [`logo-brand-transparent.svg`](logo-brand-transparent.svg) | Full lockup: mark + NOVOLIS wordmark + tagline |
| [`logo-brand-transparent-overlay.svg`](logo-brand-transparent-overlay.svg) | Feedback overlay with raster underlay, magenta outlines, numbered control points |
| [`generated/logo-mark.svg`](generated/logo-mark.svg) | Mark only, auto-cropped viewBox (no wordmark/tagline) |
| [`generated/shapes/upper.svg`](generated/shapes/upper.svg) | Single-shape export |
| [`generated/shapes/lower.svg`](generated/shapes/lower.svg) | Single-shape export |
| [`generated/shapes/n.svg`](generated/shapes/n.svg) | Single-shape export |
| [`generated/shapes/n_left.svg`](generated/shapes/n_left.svg) | Single-shape export |
| [`generated/shapes/n_right.svg`](generated/shapes/n_right.svg) | Single-shape export |
| [`generated/shapes/star.svg`](generated/shapes/star.svg) | Single-shape export |
| [`generated/logo-icon.svg`](generated/logo-icon.svg) | Square icon (512×512); viewBox from path bounds + arc margin |
| [`generated/logo-social.svg`](generated/logo-social.svg) | Social card template (1200×630) |

PNG renders (when using the `png` command) are written alongside under `generated/`.

## Reference files

- [`logo-brand-transparent.png`](logo-brand-transparent.png): raster reference for visual checking and overlay underlay.
- [`generate-pixel-outlines.cs`](generate-pixel-outlines.cs): single-file library + generator source.
