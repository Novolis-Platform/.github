#!/usr/bin/env python3
"""
Build reference mask + per-element coordinate map from the canonical PNG.

Usage:
  python reference_mask.py extract
  python reference_mask.py visualize
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from path_tools import (
    VIEWBOX,
    BBox,
    ElementMap,
    downsample_mask,
    mask_centroid,
    mask_to_viewbox_bbox,
)

BRAND = Path(__file__).resolve().parent.parent
DEFAULT_SRC = BRAND / "ChatGPT Image May 16, 2026, 07_58_23 PM.png"
REF_DIR = BRAND / "reference"
MIN_AREA = 2500
BG_RGB = np.array([11, 18, 32], dtype=np.float32)


def foreground_mask(rgb: np.ndarray, threshold: float = 35.0) -> np.ndarray:
    return np.linalg.norm(rgb.astype(np.float32) - BG_RGB, axis=2) > threshold


def detect_icon_crop(mask: np.ndarray) -> tuple[int, int, int, int]:
    """Return x0, y0, x1, y1 for symbol-only region (exclude wordmark)."""
    h, w = mask.shape
    row_cov = mask.sum(axis=1)
    text_top = h
    for y in range(h - 1, int(h * 0.35), -1):
        if row_cov[y] > w * 0.12:
            text_top = y
            break
    icon_bottom = max(int(h * 0.45), text_top - int(h * 0.02))
    sub = mask[:icon_bottom]
    if sub.sum() == 0:
        return 0, 0, w, icon_bottom
    cols = sub.sum(axis=0)
    xs = np.where(cols > 5)[0]
    x0, x1 = int(xs[0]), int(xs[-1])
    rows = sub[:, x0 : x1 + 1].sum(axis=1)
    ys = np.where(rows > 5)[0]
    y0, y1 = int(ys[0]), int(ys[-1])
    pad = int(min(w, h) * 0.02)
    return max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(icon_bottom, y1 + pad)


def normalize_bbox(x0: int, y0: int, x1: int, y1: int, cw: int, ch: int) -> BBox:
    return BBox(
        x0 / cw * VIEWBOX,
        y0 / ch * VIEWBOX,
        (x1 + 1) / cw * VIEWBOX,
        (y1 + 1) / ch * VIEWBOX,
    )


def classify_component(
    comp_id: int,
    bbox_px: tuple[int, int, int, int],
    area: int,
    cy_norm: float,
    cx_norm: float,
    cw: int,
    ch: int,
) -> str | None:
    x0, y0, x1, y1 = bbox_px
    w = (x1 - x0) / cw
    h = (y1 - y0) / ch
    if cy_norm > 0.78:
        return None  # wordmark / tagline debris
    # Star: small, upper-right (lower min area than other elements)
    if cy_norm < 0.24 and cx_norm > 0.58 and 80 <= area < 20000:
        return "star"
    if area < MIN_AREA:
        return None
    # Upper swirl: top half, wide bbox
    if cy_norm < 0.38 and w > 0.35 and area < 25000:
        return "swirl_upper"
    # Lower swirl: bottom arc
    if cy_norm > 0.55 and cy_norm < 0.82 and w > 0.2:
        return "swirl_lower"
    # N pieces (central)
    if 0.25 < cy_norm < 0.72 and 0.15 < cx_norm < 0.85:
        if cx_norm < 0.42 and w < 0.22:
            return "n_left_stem"
        if cx_norm > 0.58 and w < 0.22:
            return "n_right_stem"
        if 0.35 < cx_norm < 0.65 or area > 40000:
            return "n_diagonal"
        if area > 30000:
            return "n_body"
    return f"blob_{comp_id}"


def merge_components_by_label(
    labeled: np.ndarray,
    components: list[dict],
) -> list[dict]:
    """Merge raw CC blobs that share the same semantic label."""
    by_label: dict[str, list[dict]] = {}
    for c in components:
        lab = c["label"]
        if lab is None or lab.startswith("blob_"):
            continue
        by_label.setdefault(lab, []).append(c)
    merged: list[dict] = []
    for label, group in by_label.items():
        if len(group) == 1:
            merged.append(group[0])
            continue
        ids = [g["component_id"] for g in group]
        union = np.isin(labeled, ids)
        ys, xs = np.where(union)
        x0, x1 = int(xs.min()), int(xs.max())
        y0, y1 = int(ys.min()), int(ys.max())
        ch, cw = labeled.shape
        merged.append(
            {
                "component_ids": ids,
                "label": label,
                "id": label,
                "bbox_px": (x0, y0, x1, y1),
                "area": int(union.sum()),
                "mask": union,
            }
        )
    return merged


def extract_reference(
    src: Path,
    out_dir: Path,
    *,
    threshold: float = 35.0,
) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    im = Image.open(src).convert("RGB")
    rgb = np.array(im)
    full_mask = foreground_mask(rgb, threshold)
    x0, y0, x1, y1 = detect_icon_crop(full_mask)
    crop_rgb = rgb[y0:y1, x0:x1]
    crop_mask = foreground_mask(crop_rgb, threshold)
    ch, cw = crop_mask.shape

    # Light close to bridge anti-aliased gaps inside N
    struct = ndimage.generate_binary_structure(2, 1)
    closed = ndimage.binary_closing(crop_mask, structure=struct, iterations=1)
    labeled, n = ndimage.label(closed)

    raw_components: list[dict] = []
    for comp_id in range(1, n + 1):
        union = labeled == comp_id
        area = int(union.sum())
        if area < 80:
            continue
        ys, xs = np.where(union)
        bx = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
        cx_n = xs.mean() / cw
        cy_n = ys.mean() / ch
        label = classify_component(comp_id, bx, area, cy_n, cx_n, cw, ch)
        if label is None:
            continue
        raw_components.append(
            {
                "component_id": comp_id,
                "label": label,
                "id": label,
                "bbox_px": bx,
                "area": area,
                "mask": union,
            }
        )

    merged = merge_components_by_label(labeled, raw_components)

    # Fallback labels if heuristics missed
    if not any(m["label"] == "swirl_upper" for m in merged):
        tops = sorted(
            [c for c in raw_components if c["bbox_px"][1] / ch < 0.35],
            key=lambda c: -c["area"],
        )
        if tops:
            tops[0]["label"] = tops[0]["id"] = "swirl_upper"
            merged.append(tops[0])

    total_fg = max(1, int(crop_mask.sum()))
    elements: list[ElementMap] = []
    for m in merged:
        bx = m["bbox_px"]
        bbox = normalize_bbox(*bx, cw, ch)
        sub = m["mask"][bx[1] : bx[3] + 1, bx[0] : bx[2] + 1]
        elements.append(
            ElementMap(
                id=m["id"],
                label=m["label"],
                bbox=bbox,
                centroid=mask_centroid(m["mask"]),
                area_fraction=m["area"] / total_fg,
                mask64=downsample_mask(sub),
                component_ids=m.get("component_ids", [m.get("component_id")]),
            )
        )

    # Stable order for tests
    order = ["swirl_upper", "swirl_lower", "n_left_stem", "n_right_stem", "n_diagonal", "n_body", "star"]
    elements.sort(key=lambda e: order.index(e.label) if e.label in order else 99)

    meta = {
        "viewBox": [0, 0, 100, 100],
        "source_image": src.name,
        "crop_pixels": {"x0": x0, "y0": y0, "x1": x1, "y1": y1},
        "crop_size": {"width": cw, "height": ch},
        "threshold": threshold,
        "element_count": len(elements),
        "elements": [e.to_dict() for e in elements],
    }

    # Write mask PNG (symbol crop, white on black)
    mask_img = Image.fromarray((crop_mask.astype(np.uint8) * 255))
    mask_img.save(out_dir / "mask.png")

    labeled_viz = (labeled % 20) * 12
    labeled_viz[~closed] = 0
    Image.fromarray(labeled_viz.astype(np.uint8)).save(out_dir / "mask-labeled.png")

    crop_im = Image.fromarray(crop_rgb)
    crop_im.save(out_dir / "icon-crop.png")

    (out_dir / "elements.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    # Coordinate map summary (human-readable)
    lines = ["# Reference element coordinate map", ""]
    for e in elements:
        lines.append(f"## {e.id} ({e.label})")
        lines.append(f"- bbox: {e.bbox.to_dict()}")
        lines.append(f"- centroid: ({e.centroid[0]:.2f}, {e.centroid[1]:.2f})")
        lines.append(f"- area_fraction: {e.area_fraction:.4f}")
        lines.append("")
    (out_dir / "COORDINATE_MAP.md").write_text("\n".join(lines), encoding="utf-8")

    return meta


def visualize(out_dir: Path) -> None:
    meta = json.loads((out_dir / "elements.json").read_text(encoding="utf-8"))
    base = Image.open(out_dir / "icon-crop.png").convert("RGB")
    draw = ImageDraw.Draw(base, "RGBA")
    cw = meta["crop_size"]["width"]
    ch = meta["crop_size"]["height"]
    colors = {
        "swirl_upper": (64, 200, 255, 180),
        "swirl_lower": (64, 120, 255, 180),
        "n_left_stem": (100, 255, 150, 180),
        "n_right_stem": (180, 100, 255, 180),
        "n_diagonal": (255, 200, 80, 180),
        "n_body": (255, 120, 120, 180),
        "star": (255, 255, 100, 200),
    }
    for e in meta["elements"]:
        b = e["bbox"]
        x0 = b["x0"] / 100 * cw
        y0 = b["y0"] / 100 * ch
        x1 = b["x1"] / 100 * cw
        y1 = b["y1"] / 100 * ch
        col = colors.get(e["label"], (255, 255, 255, 120))
        draw.rectangle([x0, y0, x1, y1], outline=col[:3] + (255,), width=2)
        cx, cy = e["centroid"]["x"] / 100 * cw, e["centroid"]["y"] / 100 * ch
        draw.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=col)
        draw.text((x0 + 2, y0 + 2), e["label"], fill=(255, 255, 255, 255))
    base.save(out_dir / "elements-overlay.png")


def main() -> None:
    p = argparse.ArgumentParser(description="Reference mask tooling for Novolis logo")
    p.add_argument("command", choices=["extract", "visualize"], help="extract | visualize")
    p.add_argument("--src", type=Path, default=DEFAULT_SRC)
    p.add_argument("--out", type=Path, default=REF_DIR)
    p.add_argument("--threshold", type=float, default=35.0)
    args = p.parse_args()
    if args.command == "extract":
        meta = extract_reference(args.src, args.out, threshold=args.threshold)
        print(f"Wrote {args.out}/mask.png, elements.json ({meta['element_count']} elements)")
    else:
        visualize(args.out)
        print(f"Wrote {args.out}/elements-overlay.png")


if __name__ == "__main__":
    main()
