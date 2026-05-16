#!/usr/bin/env python3
"""Generate logo-mark.svg: mask contour → sparse corners → smooth cubic splines (6 layers)."""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from skimage.measure import find_contours
except ImportError:
    find_contours = None  # type: ignore

BRAND = Path(__file__).resolve().parent.parent
OUT = BRAND / "logo-mark.svg"
REF = BRAND / "reference" / "elements.json"

PATH_ORDER = [
    "swirl_upper",
    "swirl_lower",
    "n_right_stem",
    "n_left_stem",
    "n_diagonal",
    "star",
]

CORNER_BUDGET: dict[str, int] = {
    "swirl_upper": 10,
    "swirl_lower": 8,
    "n_right_stem": 6,
    "n_left_stem": 6,
    "n_diagonal": 12,
}

RENDER = 2048
TENSION = 0.34
STAR_CONCAVITY = 0.248


def _rdp(points: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(points) < 3:
        return points

    def perp_dist(p, a, b):
        ax, ay = a
        bx, by = b
        if ax == bx and ay == by:
            return math.hypot(p[0] - ax, p[1] - ay)
        t = max(
            0,
            min(1, ((p[0] - ax) * (bx - ax) + (p[1] - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)),
        )
        px, py = ax + t * (bx - ax), ay + t * (by - ay)
        return math.hypot(p[0] - px, p[1] - py)

    def rec(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if len(pts) < 3:
            return pts
        a, b = pts[0], pts[-1]
        idx, dmax = 0, -1.0
        for i in range(1, len(pts) - 1):
            d = perp_dist(pts[i], a, b)
            if d > dmax:
                idx, dmax = i, d
        if dmax > eps:
            return rec(pts[: idx + 1])[:-1] + rec(pts[idx:])
        return [a, b]

    closed = points if points[0] == points[-1] else points + [points[0]]
    return rec(closed)


def _rdp_to_budget(points: list[tuple[float, float]], budget: int) -> list[tuple[float, float]]:
    if len(points) <= budget + 1:
        return points[:-1] if points and points[0] == points[-1] else points
    lo, hi = 0.05, max(2.0, len(points) * 0.5)
    best = points
    for _ in range(24):
        mid = (lo + hi) / 2
        simplified = _rdp(points, mid)
        n = len(simplified) - (1 if simplified and simplified[0] == simplified[-1] else 0)
        if n > budget:
            lo = mid
        else:
            hi = mid
            best = simplified
    out = best[:-1] if best and best[0] == best[-1] else best
    if len(out) > budget:
        step = max(1, len(out) // budget)
        out = out[::step][:budget]
    return out


def _mask_contour(elem: dict, res: int = RENDER) -> list[tuple[float, float]]:
    mask = np.array(elem["mask64"], dtype=np.uint8) > 0
    b = elem["bbox"]
    x0 = int(b["x0"] / 100 * res)
    y0 = int(b["y0"] / 100 * res)
    x1 = max(x0 + 2, int(math.ceil(b["x1"] / 100 * res)))
    y1 = max(y0 + 2, int(math.ceil(b["y1"] / 100 * res)))
    patch = np.array(
        Image.fromarray((mask.astype(np.uint8) * 255)).resize((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    ) > 127
    canvas = np.zeros((res, res), dtype=np.float64)
    canvas[y0:y1, x0:x1] = patch.astype(np.float64)
    contours = find_contours(canvas, 0.5)
    if not contours:
        return []
    c = max(contours, key=len)
    pts = [(float(col) / res * 100, float(row) / res * 100) for row, col in c]
    if pts[0] != pts[-1]:
        pts.append(pts[0])
    return pts


def _catmull_rom_closed(points: list[tuple[float, float]], tension: float = TENSION) -> str:
    n = len(points)
    if n < 3:
        return ""
    parts = [f"M{points[0][0]:.2f},{points[0][1]:.2f}"]
    for i in range(n):
        p0 = points[(i - 1) % n]
        p1 = points[i]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n]
        c1x = p1[0] + (p2[0] - p0[0]) * tension
        c1y = p1[1] + (p2[1] - p0[1]) * tension
        c2x = p2[0] - (p3[0] - p1[0]) * tension
        c2y = p2[1] - (p3[1] - p1[1]) * tension
        parts.append(f"C{c1x:.2f},{c1y:.2f} {c2x:.2f},{c2y:.2f} {p2[0]:.2f},{p2[1]:.2f}")
    parts.append("Z")
    return "".join(parts)


def _star_path(elem: dict) -> str:
    b = elem["bbox"]
    c = elem["centroid"]
    cx, cy = c["x"], c["y"]
    rx = (b["x1"] - b["x0"]) / 2 * 0.94
    ry = (b["y1"] - b["y0"]) / 2 * 0.94
    tips = [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]
    parts = [f"M{tips[0][0]:.2f},{tips[0][1]:.2f}"]
    for i in range(4):
        x0, y0 = tips[i]
        x1, y1 = tips[(i + 1) % 4]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        qx = cx + (mx - cx) * STAR_CONCAVITY
        qy = cy + (my - cy) * STAR_CONCAVITY
        parts.append(f"Q{qx:.2f},{qy:.2f} {x1:.2f},{y1:.2f}")
    return "".join(parts) + "Z"


def element_to_smooth_path(elem: dict) -> str:
    label = elem["label"]
    if label == "star":
        return _star_path(elem)
    contour = _mask_contour(elem)
    if not contour:
        return ""
    budget = CORNER_BUDGET.get(label, 8)
    corners = _rdp_to_budget(contour, budget)
    tension = 0.26 if label == "n_diagonal" else TENSION
    return _catmull_rom_closed(corners, tension)


def build() -> str:
    data = json.loads(REF.read_text(encoding="utf-8"))
    by_label = {e["label"]: e for e in data["elements"]}
    paths: list[str] = []
    for label in PATH_ORDER:
        elem = by_label.get(label)
        if not elem:
            raise KeyError(f"missing reference element {label}")
        d = element_to_smooth_path(elem)
        if not d:
            raise ValueError(f"empty path for {label}")
        paths.append(d)

    body = "\n".join(f'  <path fill="url(#g)" d="{d}"/>' for d in paths)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Novolis">
  <defs>
    <linearGradient id="g" x1="14" y1="10" x2="86" y2="90" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#45d4ff"/>
      <stop offset="0.42" stop-color="#3b82f6"/>
      <stop offset="1" stop-color="#a855f7"/>
    </linearGradient>
  </defs>
{body}
</svg>
"""


def main() -> None:
    if find_contours is None:
        raise SystemExit("Install scikit-image: pip install scikit-image")
    if not REF.exists():
        raise SystemExit(f"Run reference_mask.py extract first (missing {REF})")
    OUT.write_text(build(), encoding="utf-8", newline="\n")
    print(f"Wrote {OUT} (6 mask-fitted smooth paths)")


if __name__ == "__main__":
    main()
