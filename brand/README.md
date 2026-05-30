# Novolis Brand Assets

The primary Novolis logo asset is [`logo-brand-transparent.svg`](logo-brand-transparent.svg).

It is a transparent, vector-only SVG: the mark is built from filled paths with gradients, and the wordmark/tagline are SVG text. The PNG reference remains useful for visual comparison, but it is not embedded in the SVG.

## Regenerating

Use the .NET file-based C# generator from this directory:

```powershell
dotnet run generate-pixel-outlines.cs -- logo-brand-transparent.png logo-brand-transparent.svg 16
```

The generator keeps the logo geometry as named vector points and emits SVG path data from those points. The upper swirl and three `N` shapes are treated as locked geometry; the remaining swirl segments reuse the same canonical arc radii so the taper stays consistent.

The generator also writes [`logo-brand-transparent-overlay.svg`](logo-brand-transparent-overlay.svg). Use that overlay for feedback: it places the raster reference underneath the vector shapes and labels every control point as `<shape>:<point-number>`.

## Files

- [`logo-brand-transparent.svg`](logo-brand-transparent.svg): primary transparent vector logo.
- [`logo-brand-transparent-overlay.svg`](logo-brand-transparent-overlay.svg): feedback overlay with outlines, shape labels, and control-point labels.
- [`logo-brand-transparent.png`](logo-brand-transparent.png): raster reference used for visual checking.
- [`generate-pixel-outlines.cs`](generate-pixel-outlines.cs): source for regenerating the SVG from vector points.
