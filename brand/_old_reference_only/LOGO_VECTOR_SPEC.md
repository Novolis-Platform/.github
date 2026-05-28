# Novolis logo — deterministic vector reconstruction

**Status:** Active (replaces auto-trace as source of truth)  
**Canonical artboard:** `viewBox="0 0 100 100"`  
**Machine source:** [`spec/logo-graph.json`](spec/logo-graph.json)  
**Raster reference (validation only):** [`reference/`](reference/)

The mark is a **parametric vector graph**: semantic nodes, fixed spline topologies, and explicit path recipes. PNG masks and IoU tests are **regression checks**, not generators.

---

## 1. Why not auto-trace?

| Auto-trace | Deterministic reconstruction |
|------------|------------------------------|
| Thousands of `L` segments or noisy Catmull fits | 3–8 nodes per primitive with named roles |
| Corners drift when resolution changes | Same graph at any export scale |
| No animation semantics | Nodes map to tween targets (Raylib, Avalonia, web) |
| Opaque path `d` strings | Topology + params documented in JSON |
| Chases raster aliasing | Chases design intent |

**Rule:** `extract_shape_points.py` may propose coordinates; **`spec/logo-graph.json` wins** until a human or reviewed edit updates it.

---

## 2. Layer structure (paint order)

Bottom → top in `logo-mark.svg`:

| Z | Layer ID | Topology | Node count | Notes |
|---|----------|----------|------------|-------|
| 0 | `swirl_upper` | `arc_crescent` | 4 + 2 apexes | Orbital arc, top |
| 1 | `swirl_left` | `arc_crescent` | 4 + 2 apexes | Orbital arc, left side |
| 2 | `swirl_lower` | `arc_crescent` | 4 + 2 apexes | Orbital arc, bottom |
| 3 | `swirl_right` | `arc_crescent` | 4 + 2 apexes | Orbital arc, right side |
| 4 | `n_left_stem` | `polygon` | 4 | Inner left stem |
| 5 | `n_diagonal` | `polygon` | 4 | Main diagonal bar |
| 6 | `n_right_stem` | `polygon` | 4 | Chamfered right stem |
| 7 | `star` | `star_quadratic` | 4 tips | Analytic concave sparkle |

The current mark paints `n_diagonal` and `n_right_stem` separately so the reference image's split-stem geometry remains editable.

Shared fill: `url(#g)` on every path.

---

## 3. Node / point extraction strategy

### 3.1 Per-shape isolation

1. Segment reference PNG → `reference/elements.json` (labels + mask64).  
2. Crop each label → `reference/shapes/{label}.png`.  
3. Run **label-specific detector** (`shape_detect.py`) → proposed nodes.  
4. Review on `reference/shapes/{label}-points.png`.  
5. Copy approved coords into `spec/logo-graph.json`.

Never fit all shapes from one global contour.

### 3.2 Node budgets (design intent)

| Primitive | Nodes | Semantics |
|-----------|-------|-----------|
| Upper / lower swirl | **3** | `left_outer`, `left_inner` (thick end), `right_tip` (sharp end) |
| Swirl apex | **1** meta | Outer bulge: min-Y (upper) / max-Y (lower) on mask |
| Left stem | **4** | `top_outer` → `top_inner` → `bottom_inner` → `bottom_outer` |
| Main N block | **8** | Chamfered octagon: top cap, right stem, bottom cap, left inner corners |
| Star | **4** | Cardinal tips; concavity is **math**, not extra nodes |

### 3.3 Extraction heuristics (bootstrap)

- **Swirl:** leftmost tip, rightmost tip, inner = max perpendicular distance from tip chord (exclude apex).  
- **Stem:** top/bottom 14% bands → min/max X for outer/inner vertical edges.  
- **n_main:** RDP simplify merged `n_diagonal ∪ n_right_stem` mask to 8 vertices.  
- **Star:** bbox + centroid → tips; `concavity` param for edge control.

---

## 4. Spline topology

### 4.1 `swirl_crescent` (3 nodes + apex)

```
M  left_outer
C  → apex (outer_pull) → right_tip     # outer cubic
Q  → inner (inner_pull) → left_inner   # inner quadratic toward centroid
Z
```

Params: `outer_pull` ≈ 0.88, `inner_pull` ≈ 0.42 (tune against reference mask).

### 4.2 `polygon` (stem)

```
M P1 → L P2 → L P3 → L P4 → Z
```

Straight edges only; chamfers are implicit in node placement.

### 4.3 `catmull_closed` (n_main)

Uniform Catmull–Rom → cubic Bézier through 8 nodes, closed.  
Param: `tension` ≈ 0.20 (lower = tighter on chamfers).

### 4.4 `star_quadratic` (4 tips)

For each edge tipᵢ → tipᵢ₊₁:

```
Q  control = C + k * (M - C)
```

`C` = centroid of tips, `M` = edge midpoint, `k` = `concavity` (≈ 0.248).

---

## 5. Arc reconstruction

Orbital swirls are **cubic arcs** (not elliptical `A` commands) so control points stay animatable.

Future option: fit `A rx ry` to outer swirl segment if a perfect circular orbit is required; keep nodes at tips + apex for compatibility.

Stem **outer** edge may gain a single cubic (`C`) in v2 if the trapezoid polygon is too stiff; inner edge stays straight.

---

## 6. SVG path recommendations

- One `<path>` per layer, `fill="url(#g)"`, no stroke in master mark.  
- Prefer `C` / `Q` over polylines; no `L` chains longer than 2 segments except stem polygon.  
- `viewBox="0 0 100 100"`; no `width`/`height` in master.  
- `role="img"` + `aria-label="Novolis"`.  
- No filters, clips, embedded raster, or CSS animation in canonical files.  
- Target ≤ 2 KB mark SVG after SVGO (conservative).

---

## 7. Symmetry / asymmetry rules

| Region | Rule |
|--------|------|
| Star | 4-fold diagonal symmetry in tips; **concave** edges break 90° symmetry intentionally |
| Left stem | Mirror **topology** of right stem but **not** mirror coordinates |
| Swirls | Upper/lower share topology; **not** mirror-Y (different tip positions) |
| n_main | Asymmetric 8-node octagon; right stem integrated |
| Overall icon | Roughly balanced mass; centroid near (50, 45) in viewBox units |

Do not force bilateral symmetry on the full mark.

---

## 8. Gradient system

Single shared linear gradient `id="g"` in `<defs>`:

| Stop | Color | Role |
|------|-------|------|
| 0% | `#45d4ff` | Cyan highlight (top-left) |
| 42% | `#3b82f6` | Mid blue |
| 100% | `#a855f7` | Purple (bottom-right) |

`x1,y1` → `x2,y2` ≈ `(14,10)` → `(86,90)` in user space.

Mono variants (`logo-mark-mono-dark.svg`, `favicon.svg`) swap fill to solid `#f5f5f5` or `currentColor` via `sync_mark.py`.

---

## 9. Export pipeline

```text
spec/logo-graph.json
        │
        ▼
  build_logo_mark.py  ──►  logo-mark.svg
        │
        ▼
  sync_mark.py        ──►  favicon.svg, logo-mark-mono-dark.svg, logo-brand.svg (icon group)
        │
        ▼
  build_brand_svg.py  ──►  logo-lockup-horizontal.svg
        │
        ▼
  resvg / npx         ──►  social-512.png, logo-brand-512.png
```

**Validation (optional CI):**

```bash
python reference_mask.py extract      # refresh masks only when PNG changes
python extract_shape_points.py        # writes bootstrap + debug PNGs only
python build_logo_mark.py
python logo_match.py --by-path-map
pytest brand/tests/test_logo_reference.py
```

---

## 10. Future simplification strategy

1. **Freeze nodes** in `logo-graph.json` once IoU thresholds pass.  
2. Replace Catmull `n_main` with explicit cubics per edge (8×2 controls = predictable animation).  
3. Collapse gradient to mono for package icons (`currentColor`).  
4. Add `logo-graph.schema.json` for CI validation of node counts / topology.  
5. Procedural variant: perturb `apex`, `concavity`, `tension` with seeds — topology unchanged.  
6. Raylib / Avalonia: load JSON nodes → tessellate paths → GPU buffers; same graph drives UI splash and tests.

---

## 11. Workflows

| Goal | Action |
|------|--------|
| Hand-edit SVG | Edit `logo-graph.json` nodes → `build_logo_mark.py` |
| Agent / vector tool | Pass this spec + `logo-graph.json` as constraints |
| Implement in code | `shape_points.path_from_shape_record()` topology table |
| Animate | Tween node IDs (`left_outer`, `tip_n`, …) not path re-trace |
| New reference PNG | Re-run extract → diff bootstrap vs graph → merge manually |

---

## 12. Related files

| File | Role |
|------|------|
| [`spec/logo-graph.json`](spec/logo-graph.json) | **Source of truth** |
| [`reference/shape-points.json`](reference/shape-points.json) | Last bootstrap extract (may diverge) |
| [`reference/SHAPE_POINTS.md`](reference/SHAPE_POINTS.md) | Point role glossary |
| [`reference/path-index-map.json`](reference/path-index-map.json) | SVG path index ↔ label |
| [`plans/logo.md`](../plans/logo.md) | Original brand brief (monochrome v1; gradient mark is canonical art) |
