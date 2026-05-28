#!/usr/bin/env python3
"""Per-shape mask crops and geometry-aware corner detection."""
from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

try:
    from skimage.measure import find_contours
except ImportError:
    find_contours = None  # type: ignore

from path_tools import VIEWBOX, ElementMap

SHAPES_DIR_NAME = "shapes"
PAD_PX = 8
UPSAMPLE = 8  # mask64 → 512 local


def _elem_mask(elem: ElementMap) -> np.ndarray:
    return np.array(elem.mask64, dtype=bool)


def crop_shape_mask(elem: ElementMap, *, pad: int = PAD_PX) -> tuple[np.ndarray, dict[str, float]]:
    """Binary mask in local pixel coords + viewBox offset scale."""
    mask = _elem_mask(elem)
    h, w = mask.shape
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return mask, {"ox": 0, "oy": 0, "sx": VIEWBOX / w, "sy": VIEWBOX / h}

    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(w - 1, x1 + pad)
    y1 = min(h - 1, y1 + pad)
    crop = mask[y0 : y1 + 1, x0 : x1 + 1]

    b = elem.bbox
    bw, bh = b.x1 - b.x0, b.y1 - b.y0
    sx = bw / max(crop.shape[1], 1)
    sy = bh / max(crop.shape[0], 1)
    ox = b.x0 - x0 * sx
    oy = b.y0 - y0 * sy
    return crop, {"ox": ox, "oy": oy, "sx": sx, "sy": sy, "x0": x0, "y0": y0}


def _local_to_viewbox(x: float, y: float, meta: dict[str, float]) -> tuple[float, float]:
    return meta["ox"] + x * meta["sx"], meta["oy"] + y * meta["sy"]


def _mask_to_viewbox_points(mask: np.ndarray, meta: dict[str, float]) -> list[tuple[float, float]]:
    ys, xs = np.where(mask)
    return [_local_to_viewbox(float(x), float(y), meta) for y, x in zip(ys, xs)]


def _contour_viewbox(mask: np.ndarray, meta: dict[str, float]) -> list[tuple[float, float]]:
    if find_contours is None:
        return _mask_to_viewbox_points(mask, meta)
    up = np.array(Image.fromarray(mask.astype(np.uint8) * 255).resize(
        (mask.shape[1] * UPSAMPLE, mask.shape[0] * UPSAMPLE), Image.Resampling.NEAREST
    )) > 127
    contours = find_contours(up.astype(float), 0.5)
    if not contours:
        return _mask_to_viewbox_points(mask, meta)
    c = max(contours, key=len)
    scale_x = meta["sx"] / UPSAMPLE
    scale_y = meta["sy"] / UPSAMPLE
    pts = [
        (meta["ox"] + float(col) * scale_x, meta["oy"] + float(row) * scale_y)
        for row, col in c
    ]
    if pts and pts[0] != pts[-1]:
        pts.append(pts[0])
    return pts


def _line_dist(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    ax, ay, bx, by, px, py = a[0], a[1], b[0], b[1], p[0], p[1]
    den = math.hypot(bx - ax, by - ay) or 1e-9
    return abs((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / den


def _band(pts: list[tuple[float, float]], *, frac: float, axis: str, side: str) -> list[tuple[float, float]]:
    if not pts:
        return []
    vals = [p[0] if axis == "x" else p[1] for p in pts]
    lo, hi = min(vals), max(vals)
    span = (hi - lo) * frac
    if side in ("low", "left"):
        edge = lo + span
        return [p for p in pts if (p[0] if axis == "x" else p[1]) <= edge]
    edge = hi - span
    return [p for p in pts if (p[0] if axis == "x" else p[1]) >= edge]


def detect_swirl(elem: ElementMap, *, upper: bool) -> tuple[list[tuple[float, float]], list[str], dict[str, Any]]:
    """
    Three anchors: left end (outer + inner), right tip.
    Apex stored in meta for cubic outer arc.
    """
    mask, meta = crop_shape_mask(elem)
    pts = _mask_to_viewbox_points(mask, meta)
    if not pts:
        return [], [], {}

    xs = [p[0] for p in pts]
    x_lo, x_hi = min(xs), max(xs)
    w = x_hi - x_lo or 1.0

    left = _band(pts, frac=0.35, axis="x", side="low")
    right = _band(pts, frac=0.20, axis="x", side="high")

    if upper:
        apex = min(pts, key=lambda p: p[1])
        left_outer = min(pts, key=lambda p: (p[0], p[1]))
        right_tip = max(pts, key=lambda p: (p[0], p[1]))
        inner_band = [p for p in pts if x_lo + 0.08 * w < p[0] < x_lo + 0.48 * w and p[1] > apex[1] + 1.5]
        left_inner = max(inner_band, key=lambda p: p[1]) if inner_band else left_outer
    else:
        apex = max(pts, key=lambda p: p[1])
        left_outer = min(pts, key=lambda p: (p[0], -p[1]))
        right_tip = max(pts, key=lambda p: (p[0], -p[1]))
        inner_band = [p for p in pts if x_lo + 0.08 * w < p[0] < x_lo + 0.48 * w and p[1] < apex[1] - 1.5]
        left_inner = min(inner_band, key=lambda p: p[1]) if inner_band else left_outer

    corners = [left_outer, left_inner, right_tip]
    roles = ["left_outer", "left_inner", "right_tip"]
    return corners, roles, {"apex": apex, "path": "swirl_crescent"}


def detect_stem(elem: ElementMap, *, outer_on_left: bool) -> tuple[list[tuple[float, float]], list[str], dict[str, Any]]:
    """Four corners of the chamfered stem trapezoid."""
    mask, meta = crop_shape_mask(elem)
    pts = _mask_to_viewbox_points(mask, meta)
    if not pts:
        return [], [], {}

    top = _band(pts, frac=0.14, axis="y", side="low")
    bot = _band(pts, frac=0.14, axis="y", side="high")

    if outer_on_left:
        top_outer = min(top, key=lambda p: p[0])
        top_inner = max(top, key=lambda p: p[0])
        bot_outer = min(bot, key=lambda p: p[0])
        bot_inner = max(bot, key=lambda p: p[0])
        corners = [top_outer, top_inner, bot_inner, bot_outer]
        roles = ["top_outer", "top_inner", "bottom_inner", "bottom_outer"]
    else:
        top_outer = max(top, key=lambda p: p[0])
        top_inner = min(top, key=lambda p: p[0])
        bot_outer = max(bot, key=lambda p: p[0])
        bot_inner = min(bot, key=lambda p: p[0])
        corners = [top_outer, top_inner, bot_inner, bot_outer]
        roles = ["top_outer", "top_inner", "bottom_inner", "bottom_outer"]

    return corners, roles, {"path": "polygon"}


def _rdp_ring(ring: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(ring) < 3:
        return ring

    def perp(p, a, b):
        ax, ay, bx, by = a[0], a[1], b[0], b[1]
        if ax == bx and ay == by:
            return math.hypot(p[0] - ax, p[1] - ay)
        t = max(0, min(1, ((p[0] - ax) * (bx - ax) + (p[1] - ay) * (by - ay)) / ((bx - ax) ** 2 + (by - ay) ** 2)))
        px, py = ax + t * (bx - ax), ay + t * (by - ay)
        return math.hypot(p[0] - px, p[1] - py)

    def rec(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if len(pts) < 3:
            return pts
        a, b = pts[0], pts[-1]
        idx, dmax = 0, -1.0
        for i in range(1, len(pts) - 1):
            d = perp(pts[i], a, b)
            if d > dmax:
                idx, dmax = i, d
        if dmax > eps:
            return rec(pts[: idx + 1])[:-1] + rec(pts[idx:])
        return [a, b]

    closed = ring if ring[0] == ring[-1] else ring + [ring[0]]
    out = rec(closed)
    return out[:-1] if out and out[0] == out[-1] else out


def _ring_from_contour(contour: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if not contour:
        return []
    return contour[:-1] if contour[0] == contour[-1] else list(contour)


def _nearest_index(ring: list[tuple[float, float]], target: tuple[float, float]) -> int:
    return min(range(len(ring)), key=lambda i: math.hypot(ring[i][0] - target[0], ring[i][1] - target[1]))


def _order_on_contour(ring: list[tuple[float, float]], corners: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if not ring or not corners:
        return corners
    idxs = sorted({_nearest_index(ring, c) for c in corners})
    return [ring[i] for i in idxs]


def _curvature_corners(ring: list[tuple[float, float]], n: int) -> list[tuple[float, float]]:
    if len(ring) < 4:
        return ring[:n]
    scores: list[tuple[float, int]] = []
    m = len(ring)
    for i in range(m):
        a, b, c = ring[(i - 1) % m], ring[i], ring[(i + 1) % m]
        v1 = (a[0] - b[0], a[1] - b[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        cross = v1[0] * v2[1] - v1[1] * v2[0]
        dot = v1[0] * v2[0] + v1[1] * v2[1]
        turn = math.atan2(abs(cross), dot)
        scores.append((turn, i))
    scores.sort(reverse=True)
    min_sep = max(3, m // (n * 2))
    picked: list[int] = []
    for _turn, idx in scores:
        if len(picked) >= n:
            break
        if any(min((idx - j) % m, (j - idx) % m) < min_sep for j in picked):
            continue
        picked.append(idx)
    if len(picked) < n:
        for _turn, idx in scores:
            if idx not in picked:
                picked.append(idx)
            if len(picked) >= n:
                break
    picked.sort()
    return [ring[i] for i in picked[:n]]


def detect_polygon_corners(
    mask: np.ndarray,
    meta: dict[str, float],
    n: int,
) -> list[tuple[float, float]]:
    contour = _contour_viewbox(mask, meta)
    ring = _ring_from_contour(contour)
    if len(ring) <= n:
        return ring
    lo, hi = 0.02, max(3.0, len(ring) * 0.4)
    best = ring
    for _ in range(28):
        mid = (lo + hi) / 2
        simplified = _rdp_ring(ring + [ring[0]], mid)
        m = len(simplified) - (1 if simplified and simplified[0] == simplified[-1] else 0)
        if m > n:
            lo = mid
        else:
            hi = mid
            best = simplified if simplified[0] != simplified[-1] else simplified[:-1]
    if len(best) > n:
        step = max(1, len(best) // n)
        best = best[::step][:n]
    return best


def _embed_elem(elem: ElementMap, res: int = 512) -> np.ndarray:
    canvas = np.zeros((res, res), dtype=bool)
    mask = _elem_mask(elem)
    b = elem.bbox
    x0 = int(b.x0 / VIEWBOX * res)
    y0 = int(b.y0 / VIEWBOX * res)
    x1 = max(x0 + 2, int(math.ceil(b.x1 / VIEWBOX * res)))
    y1 = max(y0 + 2, int(math.ceil(b.y1 / VIEWBOX * res)))
    patch = np.array(
        Image.fromarray((mask.astype(np.uint8) * 255)).resize((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    ) > 127
    canvas[y0:y1, x0:x1] = patch
    return canvas


def _pick(pts: list[tuple[float, float]], pred, key) -> tuple[float, float]:
    sub = [p for p in pts if pred(p)]
    if not sub:
        raise ValueError("no points in region")
    return key(sub)


def detect_n_main(diagonal: ElementMap, right_stem: ElementMap) -> tuple[list[tuple[float, float]], list[str], dict[str, Any]]:
    res = 512
    union = _embed_elem(diagonal, res) | _embed_elem(right_stem, res)
    meta = {"ox": 0.0, "oy": 0.0, "sx": VIEWBOX / res, "sy": VIEWBOX / res}
    pts = _mask_to_viewbox_points(union, meta)
    if len(pts) < 50:
        corners = detect_polygon_corners(union, meta, 8)
    else:
        top_left = _pick(pts, lambda p: p[1] < 26, lambda s: min(s, key=lambda p: (p[0], p[1])))
        top_right = _pick(
            pts, lambda p: p[1] < 24 and p[0] < 58, lambda s: max(s, key=lambda p: (p[0], p[1]))
        )
        upper_inner_right = _pick(
            pts, lambda p: p[0] > 62 and p[1] < 32, lambda s: max(s, key=lambda p: (p[0], -p[1]))
        )
        lower_inner_right = _pick(
            pts, lambda p: p[0] > 62 and 44 < p[1] < 54, lambda s: max(s, key=lambda p: (p[0], p[1]))
        )
        bottom_right = _pick(
            pts, lambda p: p[1] > 54 and 38 < p[0] < 68, lambda s: max(s, key=lambda p: p[1])
        )
        bottom_left = _pick(
            pts, lambda p: p[1] > 58 and p[0] < 48, lambda s: max(s, key=lambda p: p[1])
        )
        lower_inner_left = _pick(
            pts, lambda p: p[0] < 32 and 36 < p[1] < 56, lambda s: min(s, key=lambda p: (p[0], -p[1]))
        )
        upper_inner_left = _pick(
            pts, lambda p: p[0] < 34 and 22 < p[1] < 42, lambda s: min(s, key=lambda p: (p[0], p[1]))
        )
        corners = [
            top_left,
            top_right,
            upper_inner_right,
            lower_inner_right,
            bottom_right,
            bottom_left,
            lower_inner_left,
            upper_inner_left,
        ]
    roles = [
        "top_left",
        "top_right",
        "upper_inner_right",
        "lower_inner_right",
        "bottom_right",
        "bottom_left",
        "lower_inner_left",
        "upper_inner_left",
    ][: len(corners)]
    return corners, roles, {"path": "catmull"}


def detect_for_label(label: str, by_label: dict[str, ElementMap]) -> tuple[list[tuple[float, float]], list[str], dict[str, Any]]:
    if label == "swirl_upper":
        return detect_swirl(by_label[label], upper=True)
    if label == "swirl_lower":
        return detect_swirl(by_label[label], upper=False)
    if label == "n_left_stem":
        return detect_stem(by_label[label], outer_on_left=True)
    if label == "n_right_stem":
        return detect_stem(by_label[label], outer_on_left=False)
    if label == "n_diagonal":
        mask, meta = crop_shape_mask(by_label[label])
        c = detect_polygon_corners(mask, meta, 8)
        roles = [
            "top_left",
            "top_right",
            "upper_inner_right",
            "lower_inner_right",
            "bottom_right",
            "bottom_left",
            "lower_inner_left",
            "upper_inner_left",
        ][: len(c)]
        return c, roles, {"path": "catmull"}
    if label == "n_main":
        return detect_n_main(by_label["n_diagonal"], by_label["n_right_stem"])
    raise KeyError(label)


def save_shape_crops(by_label: dict[str, ElementMap], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for label, elem in by_label.items():
        mask, _ = crop_shape_mask(elem)
        im = Image.fromarray((mask.astype(np.uint8) * 255))
        im.save(out_dir / f"{label}.png")


def render_shape_debug(
    label: str,
    elem: ElementMap | None,
    points: list[tuple[float, float]],
    roles: list[str],
    meta_extra: dict[str, Any],
    out_path: Path,
    *,
    mask_override: np.ndarray | None = None,
    meta_override: dict[str, float] | None = None,
) -> None:
    if mask_override is not None and meta_override is not None:
        mask, m = mask_override, meta_override
    elif elem is not None:
        mask, m = crop_shape_mask(elem)
    else:
        raise ValueError("elem or mask_override required")
    up = np.array(
        Image.fromarray(mask.astype(np.uint8) * 255).resize(
            (mask.shape[1] * 4, mask.shape[0] * 4), Image.Resampling.NEAREST
        )
    )
    im = Image.fromarray(up).convert("RGB")
    draw = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
    except OSError:
        font = ImageFont.load_default()

    def to_px(vb: tuple[float, float]) -> tuple[float, float]:
        lx = (vb[0] - m["ox"]) / m["sx"]
        ly = (vb[1] - m["oy"]) / m["sy"]
        return lx * 4, ly * 4

    apex = meta_extra.get("apex")
    if apex:
        ax, ay = to_px(apex)
        draw.ellipse([ax - 4, ay - 4, ax + 4, ay + 4], fill=(255, 128, 0))

    px_pts = [to_px(p) for p in points]
    for i, ((x, y), role) in enumerate(zip(px_pts, roles)):
        draw.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(0, 255, 128), outline=(0, 0, 0))
        draw.text((x + 6, y - 8), f"P{i + 1}", fill=(255, 255, 255), font=font)
    if len(px_pts) >= 2:
        loop = px_pts + [px_pts[0]]
        draw.line(loop, fill=(0, 200, 255), width=1)
    im.save(out_path)
