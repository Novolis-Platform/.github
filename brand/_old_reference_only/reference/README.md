# Logo reference mask & verification

**Vector source of truth:** [`../spec/logo-graph.json`](../spec/logo-graph.json) — see [`../LOGO_VECTOR_SPEC.md`](../LOGO_VECTOR_SPEC.md).

Raster canonical: `../ChatGPT Image May 16, 2026, 07_58_23 PM.png` (validation only).

## Artifacts

| File | Description |
|------|-------------|
| `mask.png` | Binary mask of the symbol (icon crop, no wordmark) |
| `icon-crop.png` | RGB crop used for extraction |
| `elements.json` | Disconnected elements with viewBox coordinates + 64×64 masks |
| `COORDINATE_MAP.md` | Human-readable bbox/centroid per element |
| `path-index-map.json` | Maps `logo-mark.svg` path index → reference label |
| `elements-overlay.png` | Debug visualization (run `visualize`) |
| `shape-points.json` | Corner map (P1…Pn) per shape in viewBox units |
| `mask-points.png` | Numbered corners overlaid on `icon-crop.png` |
| `SHAPE_POINTS.md` | Point roles and counts (8-point `n_main`, etc.) |
| `baselines/logo-mark.json` | Regression scores for CI |

## Commands

From `brand/scripts/`:

```bash
# 1. Build mask + element coordinate map from PNG
python reference_mask.py extract
python reference_mask.py visualize

# 2. Build mark from deterministic graph (preferred)
pip install -r ../requirements-dev.txt
python build_logo_mark.py        # reads spec/logo-graph.json
python sync_mark.py

# Optional: bootstrap node proposals from masks (merge into logo-graph.json by hand)
python extract_shape_points.py

# 3. Compare candidate SVG (diagnostic JSON)
python logo_match.py --by-path-map

# 4. Run tests (requires Node/npx for resvg)
cd ..
python -m pytest tests/ -v
```

## Path tools (`scripts/path_tools.py`)

- `parse_paths(svg)` — list path `d` attributes
- `render_svg_to_mask(svg)` — rasterize via resvg/npx
- `embed_element_mask(element, shape)` — place reference mask64 at bbox
- `iou`, `bbox_iou`, `centroid_distance`
- `compare_by_path_map(svg, elements.json, path-index-map.json)` — per-path verification
- `compare_to_reference(...)` — greedy IoU matching (optional)

## Regenerating baseline

When you intentionally improve the mark:

```bash
python logo_match.py --by-path-map --report ../reference/baselines/logo-mark.json
```

Commit the updated baseline with the SVG change.
