#!/usr/bin/env python3
"""Generate logo-mark.svg by tracing reference/elements.json masks."""
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
RENDER = 512
SIMPLIFY_EPS = 0.35


def _rdp(points: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(points) < 3:
        return points

    def perp_dist(p, a, b):
        ax, ay = a
        bx, by = b
        if ax == bx and ay == by:
            return math.hypot(p[0] - ax, p[1] - ay)
        t = max(0, min(1, ((p[0] - ax) * (bx - ax) + (p[1] - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)))
        px, py = ax + t * (bx - ax), ay + t * (by - ay)
        return math.hypot(p[0] - px, p[1] - py)

    def rdp_rec(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if len(pts) < 3:
            return pts
        a, b = pts[0], pts[-1]
        idx, dmax = 0, -1.0
        for i in range(1, len(pts) - 1):
            d = perp_dist(pts[i], a, b)
            if d > dmax:
                idx, dmax = i, d
        if dmax > eps:
            left = rdp_rec(pts[: idx + 1])
            right = rdp_rec(pts[idx:])
            return left[:-1] + right
        return [a, b]

    closed = points[:-1] if points[0] == points[-1] else points
    simplified = rdp_rec(closed + [closed[0]])
    return simplified


def _pts_to_path(pts: list[tuple[float, float]]) -> str:
    if len(pts) < 3:
        return ""
    x0, y0 = pts[0]
    parts = [f"M{x0:.2f},{y0:.2f}"]
    parts.extend(f"L{x:.2f},{y:.2f}" for x, y in pts[1:])
    return "".join(parts) + "Z"


def element_to_path(elem: dict, res: int = RENDER) -> str:
    """Trace reference mask64 into a viewBox 0–100 SVG path."""
    mask = np.array(elem["mask64"], dtype=np.uint8) > 0
    b = elem["bbox"]
    x0 = int(b["x0"] / 100 * res)
    y0 = int(b["y0"] / 100 * res)
    x1 = max(x0 + 2, int(math.ceil(b["x1"] / 100 * res)))
    y1 = max(y0 + 2, int(math.ceil(b["y1"] / 100 * res)))
    pw, ph = x1 - x0, y1 - y0
    patch = np.array(
        Image.fromarray((mask.astype(np.uint8) * 255)).resize((pw, ph), Image.Resampling.LANCZOS)
    ) > 127

    canvas = np.zeros((res, res), dtype=np.float64)
    canvas[y0:y1, x0:x1] = patch.astype(np.float64)

    if find_contours is None:
        raise RuntimeError("scikit-image required: pip install scikit-image")

    contours = find_contours(canvas, 0.5)
    if not contours:
        return ""
    contour = max(contours, key=len)
    pts = [(float(col) / res * 100, float(row) / res * 100) for row, col in contour]
    pts = _rdp(pts, SIMPLIFY_EPS)
    if pts and pts[0] != pts[-1]:
        pts.append(pts[0])
    return _pts_to_path(pts)


def build() -> str:
    data = json.loads(REF.read_text(encoding="utf-8"))
    by_label = {e["label"]: e for e in data["elements"]}
    paths: list[str] = []
    for label in PATH_ORDER:
        elem = by_label.get(label)
        if not elem:
            raise KeyError(f"missing reference element {label}")
        d = element_to_path(elem)
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
    print(f"Wrote {OUT} (traced from {REF.name})")


if __name__ == "__main__":
    main()
