#!/usr/bin/env python3
"""Corner-point extraction from per-shape mask crops."""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from path_tools import VIEWBOX, ElementMap, load_reference_elements
from shape_detect import (
    SHAPES_DIR_NAME,
    detect_for_label,
    render_shape_debug,
    save_shape_crops,
)

BRAND = Path(__file__).resolve().parent.parent
REF = BRAND / "reference"

POINT_BUDGET: dict[str, int] = {
    "swirl_upper": 3,
    "swirl_lower": 3,
    "n_left_stem": 4,
    "n_right_stem": 4,
    "n_diagonal": 8,
    "n_main": 8,
    "star": 4,
}

STAR_CONCAVITY = 0.248


def star_tips(elem: ElementMap | dict[str, Any], *, inset: float = 0.94) -> tuple[tuple[float, float], ...]:
    if isinstance(elem, ElementMap):
        b, c = elem.bbox, elem.centroid
    else:
        b = elem["bbox"]
        c = (elem["centroid"]["x"], elem["centroid"]["y"])
    cx, cy = c[0], c[1]
    rx = (b.x1 - b.x0 if hasattr(b, "x1") else b["x1"] - b["x0"]) / 2 * inset
    ry = (b.y1 - b.y0 if hasattr(b, "y1") else b["y1"] - b["y0"]) / 2 * inset
    return ((cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy))


def star_quadratic_path(
    tips: tuple[tuple[float, float], ...] | list[tuple[float, float]],
    *,
    concavity: float = STAR_CONCAVITY,
) -> str:
    if len(tips) != 4:
        raise ValueError("star requires exactly 4 tips")
    cx = sum(p[0] for p in tips) / 4
    cy = sum(p[1] for p in tips) / 4
    parts = [f"M{tips[0][0]:.2f},{tips[0][1]:.2f}"]
    for i in range(4):
        x0, y0 = tips[i]
        x1, y1 = tips[(i + 1) % 4]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        qx = cx + (mx - cx) * concavity
        qy = cy + (my - cy) * concavity
        parts.append(f"Q{qx:.2f},{qy:.2f} {x1:.2f},{y1:.2f}")
    return "".join(parts) + "Z"


def swirl_crescent_path(
    left_outer: tuple[float, float],
    left_inner: tuple[float, float],
    right_tip: tuple[float, float],
    apex: tuple[float, float],
    *,
    inner_pull: float = 0.42,
    outer_pull: float = 0.88,
) -> str:
    """3 anchors + apex: outer cubic through apex, inner quadratic pinched inward."""
    lo, li, rt, ap = left_outer, left_inner, right_tip, apex
    c1x = lo[0] + (ap[0] - lo[0]) * outer_pull
    c1y = lo[1] + (ap[1] - lo[1]) * outer_pull
    c2x = rt[0] + (ap[0] - rt[0]) * outer_pull
    c2y = rt[1] + (ap[1] - rt[1]) * outer_pull
    cx = (lo[0] + li[0] + rt[0]) / 3
    cy = (lo[1] + li[1] + rt[1]) / 3
    mx, my = (rt[0] + li[0]) / 2, (rt[1] + li[1]) / 2
    qx = cx + (mx - cx) * inner_pull
    qy = cy + (my - cy) * inner_pull
    return (
        f"M{lo[0]:.2f},{lo[1]:.2f}"
        f"C{c1x:.2f},{c1y:.2f} {c2x:.2f},{c2y:.2f} {rt[0]:.2f},{rt[1]:.2f}"
        f"Q{qx:.2f},{qy:.2f} {li[0]:.2f},{li[1]:.2f}Z"
    )


def _catmull_rom_closed(points: list[tuple[float, float]], tension: float) -> str:
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


def polygon_path(points: list[tuple[float, float]]) -> str:
    if not points:
        return ""
    parts = [f"M{points[0][0]:.2f},{points[0][1]:.2f}"]
    for x, y in points[1:]:
        parts.append(f"L{x:.2f},{y:.2f}")
    return "".join(parts) + "Z"


def path_from_shape_record(shape: dict[str, Any]) -> str:
    pts = [(p["x"], p["y"]) for p in shape["points"]]
    kind = shape.get("path", "catmull")
    if kind == "swirl_crescent":
        apex = shape.get("apex")
        if not apex or len(pts) != 3:
            raise ValueError("swirl needs 3 points + apex")
        return swirl_crescent_path(pts[0], pts[1], pts[2], (apex["x"], apex["y"]))
    if kind == "polygon":
        return polygon_path(pts)
    if kind == "star":
        return star_quadratic_path(pts, concavity=float(shape.get("concavity", STAR_CONCAVITY)))
    tension = float(shape.get("tension", 0.25))
    return _catmull_rom_closed(pts, tension)


def _shape_to_record(
    label: str,
    corners: list[tuple[float, float]],
    roles: list[str],
    extra: dict[str, Any],
    source: str,
) -> dict[str, Any]:
    rec: dict[str, Any] = {
        "label": label,
        "point_count": len(corners),
        "source": source,
        "path": extra.get("path", "catmull"),
        "points": [
            {"id": f"P{i + 1}", "role": roles[i] if i < len(roles) else f"p{i + 1}", "x": round(corners[i][0], 2), "y": round(corners[i][1], 2)}
            for i in range(len(corners))
        ],
    }
    if "apex" in extra:
        ap = extra["apex"]
        rec["apex"] = {"x": round(ap[0], 2), "y": round(ap[1], 2)}
    if label == "n_main":
        rec["tension"] = 0.20
    elif label == "n_left_stem":
        rec["path"] = extra.get("path", "polygon")
    elif label.startswith("swirl_"):
        rec["path"] = "swirl_crescent"
    return rec


def extract_shape_points(
    elements: list[ElementMap] | None = None,
    *,
    ref_json: Path | None = None,
    shapes_dir: Path | None = None,
) -> dict[str, Any]:
    if elements is None:
        elements = load_reference_elements(ref_json or REF / "elements.json")
    by_label = {e.label: e for e in elements}
    out_shapes = shapes_dir or REF / SHAPES_DIR_NAME
    save_shape_crops(by_label, out_shapes)

    shapes: list[dict[str, Any]] = []
    for label in ("swirl_upper", "swirl_lower", "n_left_stem", "n_right_stem", "n_diagonal"):
        if label not in by_label:
            continue
        corners, roles, extra = detect_for_label(label, by_label)
        rec = _shape_to_record(label, corners, roles, extra, f"per-shape mask crop ({out_shapes.name}/{label}.png)")
        shapes.append(rec)
        render_shape_debug(label, by_label[label], corners, roles, extra, out_shapes / f"{label}-points.png")

    if "star" in by_label:
        tips = star_tips(by_label["star"])
        shapes.append(
            {
                "label": "star",
                "point_count": 4,
                "source": "analytic 4-tip star",
                "path": "star",
                "concavity": STAR_CONCAVITY,
                "points": [
                    {"id": f"P{i + 1}", "role": r, "x": round(tips[i][0], 2), "y": round(tips[i][1], 2)}
                    for i, r in enumerate(["tip_n", "tip_e", "tip_s", "tip_w"])
                ],
            }
        )

    if "n_diagonal" in by_label and "n_right_stem" in by_label:
        corners, roles, extra = detect_for_label("n_main", by_label)
        rec = _shape_to_record(
            "n_main",
            corners,
            roles,
            extra,
            "merged n_diagonal + n_right_stem mask (8-point RDP)",
        )
        shapes.append(rec)
        from shape_detect import _embed_elem, detect_polygon_corners

        union = _embed_elem(by_label["n_diagonal"]) | _embed_elem(by_label["n_right_stem"])
        meta = {"ox": 0.0, "oy": 0.0, "sx": VIEWBOX / 512, "sy": VIEWBOX / 512}
        render_shape_debug(
            "n_main",
            None,
            corners,
            roles,
            extra,
            out_shapes / "n_main-points.png",
            mask_override=union,
            meta_override=meta,
        )

    return {
        "viewBox": [0, 0, 100, 100],
        "guide": "Per-shape mask crops in reference/shapes/; swirls=3 corners + apex, stem=4, n_main=8.",
        "point_budget": POINT_BUDGET,
        "shapes": shapes,
    }


def write_shape_points(out_path: Path | None = None) -> dict[str, Any]:
    data = extract_shape_points()
    out = out_path or REF / "shape-points.json"
    out.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return data


def render_points_overlay(
    data: dict[str, Any],
    *,
    base_image: Path | None = None,
    out_path: Path | None = None,
) -> Path:
    base_path = base_image or REF / "icon-crop.png"
    im = Image.open(base_path).convert("RGB")
    draw = ImageDraw.Draw(im)
    cw, ch = im.size
    colors = {
        "swirl_upper": (64, 200, 255),
        "swirl_lower": (64, 120, 255),
        "n_left_stem": (100, 255, 150),
        "n_right_stem": (180, 100, 255),
        "n_diagonal": (255, 200, 80),
        "n_main": (255, 140, 40),
        "star": (255, 255, 100),
    }
    try:
        font = ImageFont.truetype("arial.ttf", 11)
    except OSError:
        font = ImageFont.load_default()

    logo_labels = {"swirl_upper", "swirl_lower", "n_left_stem", "n_main", "star"}
    for shape in data["shapes"]:
        if shape["label"] not in logo_labels and shape["label"] != "n_diagonal":
            continue
        col = colors.get(shape["label"], (255, 255, 255))
        pts = shape["points"]
        for pt in pts:
            x = pt["x"] / VIEWBOX * cw
            y = pt["y"] / VIEWBOX * ch
            r = 5
            draw.ellipse([x - r, y - r, x + r, y + r], fill=col, outline=(0, 0, 0))
            draw.text((x + 6, y - 6), pt["id"], fill=(255, 255, 255), font=font)
        if shape.get("apex"):
            ax = shape["apex"]["x"] / VIEWBOX * cw
            ay = shape["apex"]["y"] / VIEWBOX * ch
            draw.ellipse([ax - 4, ay - 4, ax + 4, ay + 4], fill=(255, 160, 0))
        try:
            d = path_from_shape_record(shape)
            # sample path roughly by re-parsing - skip; line between points for debug
        except Exception:
            pass
        if len(pts) >= 2 and shape.get("path") != "star":
            xy = [(p["x"] / VIEWBOX * cw, p["y"] / VIEWBOX * ch) for p in pts]
            if shape.get("path") != "swirl_crescent":
                xy.append(xy[0])
            draw.line(xy, fill=col, width=1)

    out = out_path or REF / "mask-points.png"
    im.save(out)
    return out


def corners_for_label(data: dict[str, Any], label: str) -> list[tuple[float, float]]:
    for shape in data["shapes"]:
        if shape["label"] == label:
            return [(p["x"], p["y"]) for p in shape["points"]]
    raise KeyError(f"no shape points for {label}")
