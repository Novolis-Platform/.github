# Shape corner map (icon)

Derived from `mask-labeled.png` / `elements.json` masks. Regenerate with:

```bash
cd brand/scripts
python extract_shape_points.py
```

Outputs:

- `shape-points.json` — viewBox coordinates for each shape
- `mask-points.png` — numbered overlay on `icon-crop.png`

## Point budgets

| Shape | Points | Used in `logo-mark.svg` |
|-------|--------|-------------------------|
| `swirl_upper` | **3** (+ apex) | path 0 — cubic outer, quadratic inner |
| `swirl_lower` | **3** (+ apex) | path 1 |
| `n_left_stem` | **4** | path 2 — chamfered trapezoid |
| `n_right_stem` | 6 | reference only |
| `n_diagonal` | 8 | reference only (diagonal bar alone) |
| `n_main` | 8 | path 3 (`n_diagonal` ∪ `n_right_stem`) |
| `star` | **4** | path 4 — cardinal tips only; concave edges are math (quadratic toward centroid) |

## `n_main` — the 8-point silhouette

Clockwise from the top-left of the diagonal bar:

1. **P1** `top_left` — start of flat top cap  
2. **P2** `top_right` — end of top cap  
3. **P3** `upper_inner_right` — step before right stem / outer orbit  
4. **P4** `lower_inner_right` — foot of right stem  
5. **P5** `bottom_right` — bottom-right of diagonal  
6. **P6** `bottom_left` — flat bottom cap  
7. **P7** `lower_inner_left` — inner corner above bottom cap  
8. **P8** `upper_inner_left` — inner corner below top cap  

Fitted from diagonal mask corners plus the outer edge of `n_right_stem`.

## Stems — 6 points each

**Left stem:** top-inner, top-outer, outer mid, bottom-outer, bottom-inner, bottom (chamfer).  
**Right stem:** same roles on the mirrored outer/inner edges.

## Swirls — 3 points + apex

Per-shape mask in `reference/shapes/{label}.png`:

- **P1** `left_outer` — outer tip on the thick (left) end  
- **P2** `left_inner` — inner corner on the same end  
- **P3** `right_tip` — sharp tip on the right  
- **apex** — outer bulge (topmost for upper, bottommost for lower)

Path: cubic along outer arc via apex, quadratic back along inner edge.

## Star — 4 tips (concave edges are not corners)

Tips **P1–P4** on the reference bbox axes (N, E, S, W), centered on the mask centroid.

Each edge is one quadratic Bézier from tipᵢ to tipᵢ₊₁ with control point:

`Q = C + k × (M − C)`

where **C** is the centroid, **M** is the chord midpoint, and **k** ≈ `0.31` (`concavity` in `shape-points.json`). Lower **k** = deeper pinch toward the center.
