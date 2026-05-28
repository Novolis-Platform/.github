#!/usr/bin/env python3
"""SVG path utilities: parse, rasterize, normalize coordinates, compare masks."""
from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterator

import numpy as np
from PIL import Image

VIEWBOX = 100.0
SVG_NS = "http://www.w3.org/2000/svg"


@dataclass
class BBox:
    x0: float
    y0: float
    x1: float
    y1: float

    @property
    def width(self) -> float:
        return self.x1 - self.x0

    @property
    def height(self) -> float:
        return self.y1 - self.y0

    @property
    def centroid(self) -> tuple[float, float]:
        return ((self.x0 + self.x1) / 2, (self.y0 + self.y1) / 2)

    def to_dict(self) -> dict[str, float]:
        return {"x0": self.x0, "y0": self.y0, "x1": self.x1, "y1": self.y1}


@dataclass
class PathSpec:
    index: int
    d: str
    fill: str | None
    element_id: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "index": self.index,
            "d": self.d,
            "fill": self.fill,
            "element_id": self.element_id,
        }


@dataclass
class ElementMap:
    """Coordinate map for one disconnected reference or candidate shape."""

    id: str
    label: str
    bbox: BBox
    centroid: tuple[float, float]
    area_fraction: float
    mask64: list[list[int]]  # 64x64 binary
    path_index: int | None = None
    component_ids: list[int] | None = None

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "id": self.id,
            "label": self.label,
            "bbox": self.bbox.to_dict(),
            "centroid": {"x": self.centroid[0], "y": self.centroid[1]},
            "area_fraction": self.area_fraction,
            "mask64": self.mask64,
        }
        if self.path_index is not None:
            d["path_index"] = self.path_index
        if self.component_ids is not None:
            d["component_ids"] = self.component_ids
        return d

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ElementMap:
        b = data["bbox"]
        c = data["centroid"]
        return cls(
            id=data["id"],
            label=data["label"],
            bbox=BBox(b["x0"], b["y0"], b["x1"], b["y1"]),
            centroid=(c["x"], c["y"]),
            area_fraction=data["area_fraction"],
            mask64=data["mask64"],
            path_index=data.get("path_index"),
            component_ids=data.get("component_ids"),
        )


def _local_tag(tag: str) -> str:
    return tag.split("}")[-1] if "}" in tag else tag


def parse_paths(svg_text: str) -> list[PathSpec]:
    root = ET.fromstring(svg_text)
    specs: list[PathSpec] = []
    for i, el in enumerate(root.iter()):
        if _local_tag(el.tag) != "path":
            continue
        d = el.get("d")
        if not d or not d.strip():
            continue
        specs.append(
            PathSpec(
                index=len(specs),
                d=d.strip(),
                fill=el.get("fill"),
                element_id=el.get("id"),
            )
        )
    return specs


def path_only_svg(path: PathSpec, viewbox: float = VIEWBOX) -> str:
    return f'''<svg xmlns="{SVG_NS}" viewBox="0 0 {viewbox} {viewbox}">
  <rect width="{viewbox}" height="{viewbox}" fill="#000"/>
  <path fill="#ffffff" d="{path.d}"/>
</svg>'''


def extract_defs(svg_text: str) -> str:
    m = re.search(r"<defs>.*?</defs>", svg_text, re.S)
    return m.group(0) if m else ""


def path_with_defs_svg(path: PathSpec, defs: str, viewbox: float = VIEWBOX) -> str:
    fill = path.fill or "url(#g)"
    return f'''<svg xmlns="{SVG_NS}" viewBox="0 0 {viewbox} {viewbox}">
  {defs}
  <rect width="{viewbox}" height="{viewbox}" fill="#000"/>
  <path fill="{fill}" d="{path.d}"/>
</svg>'''


def _resvg_command(svg_file: Path, png_file: Path, size: int) -> list[str] | str:
    resvg_bin = shutil.which("resvg")
    if resvg_bin:
        return [
            resvg_bin,
            str(svg_file),
            str(png_file),
            "--fit-width",
            str(size),
            "--fit-height",
            str(size),
        ]
    npx = shutil.which("npx") or shutil.which("npx.cmd")
    if not npx:
        raise RuntimeError("resvg or npx not found; install Node.js or resvg CLI")
    # npx on Windows is often npx.cmd — invoke via shell when needed
    inner = (
        f'"{npx}" --yes @resvg/resvg-js-cli "{svg_file}" "{png_file}" '
        f"--fit-width {size} --fit-height {size}"
    )
    return inner if sys.platform == "win32" else [
        npx,
        "--yes",
        "@resvg/resvg-js-cli",
        str(svg_file),
        str(png_file),
        "--fit-width",
        str(size),
        "--fit-height",
        str(size),
    ]


def render_svg_to_mask(
    svg_content: str,
    size: int = 256,
) -> np.ndarray:
    """Rasterize SVG to a boolean foreground mask (white shapes on black)."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        svg_file = tmp_path / "in.svg"
        png_file = tmp_path / "out.png"
        svg_file.write_text(svg_content, encoding="utf-8")
        cmd = _resvg_command(svg_file, png_file, size)
        subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            shell=isinstance(cmd, str),
        )
        arr = np.array(Image.open(png_file).convert("L"))
    return arr > 32


def mask_to_viewbox_bbox(mask: np.ndarray) -> BBox:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return BBox(0, 0, 0, 0)
    h, w = mask.shape
    return BBox(
        xs.min() / w * VIEWBOX,
        ys.min() / h * VIEWBOX,
        (xs.max() + 1) / w * VIEWBOX,
        (ys.max() + 1) / h * VIEWBOX,
    )


def mask_centroid(mask: np.ndarray) -> tuple[float, float]:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return (0.0, 0.0)
    h, w = mask.shape
    return (xs.mean() / w * VIEWBOX, ys.mean() / h * VIEWBOX)


def downsample_mask(mask: np.ndarray, size: int = 64) -> list[list[int]]:
    im = Image.fromarray((mask.astype(np.uint8) * 255))
    small = np.array(im.resize((size, size), Image.Resampling.BILINEAR)) > 127
    return small.astype(int).tolist()


def iou(a: np.ndarray, b: np.ndarray) -> float:
    if a.shape != b.shape:
        b_img = Image.fromarray((b.astype(np.uint8) * 255))
        b = np.array(b_img.resize((a.shape[1], a.shape[0]), Image.Resampling.NEAREST)) > 127
    inter = np.logical_and(a, b).sum()
    union = np.logical_or(a, b).sum()
    return float(inter / union) if union else (1.0 if inter == 0 else 0.0)


def bbox_iou(a: BBox, b: BBox) -> float:
    ix0, iy0 = max(a.x0, b.x0), max(a.y0, b.y0)
    ix1, iy1 = min(a.x1, b.x1), min(a.y1, b.y1)
    if ix1 <= ix0 or iy1 <= iy0:
        return 0.0
    inter = (ix1 - ix0) * (iy1 - iy0)
    ua = a.width * a.height + b.width * b.height - inter
    return inter / ua if ua else 0.0


def centroid_distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return float(np.hypot(a[0] - b[0], a[1] - b[1]))


def upsample_mask64(mask64: list[list[int]], shape: tuple[int, int]) -> np.ndarray:
    im = Image.fromarray((np.array(mask64, dtype=np.uint8) * 255))
    return np.array(im.resize((shape[1], shape[0]), Image.Resampling.NEAREST)) > 127


def embed_element_mask(elem: ElementMap, shape: tuple[int, int]) -> np.ndarray:
    """Place element mask64 into full raster using its viewBox bbox."""
    h, w = shape
    full = np.zeros((h, w), dtype=bool)
    arr = np.array(elem.mask64, dtype=bool)
    x0 = int(elem.bbox.x0 / VIEWBOX * w)
    y0 = int(elem.bbox.y0 / VIEWBOX * h)
    x1 = max(x0 + 1, int(math.ceil(elem.bbox.x1 / VIEWBOX * w)))
    y1 = max(y0 + 1, int(math.ceil(elem.bbox.y1 / VIEWBOX * h)))
    patch = np.array(
        Image.fromarray(arr.astype(np.uint8) * 255).resize((x1 - x0, y1 - y0), Image.Resampling.NEAREST)
    ) > 127
    full[y0:y1, x0:x1] = patch
    return full


def rasterize_paths(
    svg_text: str,
    size: int = 256,
    *,
    use_gradient: bool = True,
) -> list[np.ndarray]:
    paths = parse_paths(svg_text)
    defs = extract_defs(svg_text) if use_gradient else ""
    masks = []
    for p in paths:
        content = path_with_defs_svg(p, defs) if use_gradient and defs and p.fill and "url(" in p.fill else path_only_svg(p)
        masks.append(render_svg_to_mask(content, size=size))
    return masks


def map_paths_to_elements(
    path_masks: list[np.ndarray],
    reference: list[ElementMap],
) -> dict[str, int]:
    """Match reference elements to path indices by maximum mask IoU (Hungarian-style greedy)."""
    shape = path_masks[0].shape
    ref_masks = [embed_element_mask(e, shape) for e in reference]
    pairs: list[tuple[float, str, int]] = []
    for elem, ref_m in zip(reference, ref_masks):
        for i, pm in enumerate(path_masks):
            pairs.append((iou(ref_m, pm), elem.id, i))
    pairs.sort(reverse=True)
    mapping: dict[str, int] = {}
    used_paths: set[int] = set()
    for score, elem_id, pi in pairs:
        if elem_id in mapping or pi in used_paths:
            continue
        if score < 0.05:
            continue
        mapping[elem_id] = pi
        used_paths.add(pi)
    return mapping


def compare_to_reference(
    candidate_svg: Path | str,
    reference_json: Path | str,
    *,
    render_size: int = 256,
    min_element_iou: float = 0.45,
    max_centroid_delta: float = 6.0,
    min_overall_iou: float = 0.55,
) -> dict[str, Any]:
    """Return a report dict; raises AssertionError only when called from tests."""
    ref_path = Path(reference_json)
    data = json.loads(ref_path.read_text(encoding="utf-8"))
    reference = [ElementMap.from_dict(e) for e in data["elements"]]

    svg_text = Path(candidate_svg).read_text(encoding="utf-8") if isinstance(candidate_svg, Path) else candidate_svg
    paths = parse_paths(svg_text)
    path_masks = rasterize_paths(svg_text, size=render_size)

    defs = extract_defs(svg_text)
    body_paths = "\n".join(f'  <path fill="url(#g)" d="{p.d}"/>' for p in paths)
    full_svg = f'<svg xmlns="{SVG_NS}" viewBox="0 0 100 100">{defs}<rect width="100" height="100" fill="#000"/>{body_paths}</svg>'
    full_mask = render_svg_to_mask(full_svg, size=render_size)

    ref_union = np.zeros_like(full_mask, dtype=bool)
    for e in reference:
        ref_union |= embed_element_mask(e, full_mask.shape)

    overall_iou = iou(ref_union, full_mask)
    path_map = map_paths_to_elements(path_masks, reference)

    per_element: list[dict[str, Any]] = []
    all_ok = True
    for elem in reference:
        ref_m = embed_element_mask(elem, full_mask.shape)
        pi = path_map.get(elem.id)
        if pi is None:
            per_element.append({"id": elem.id, "label": elem.label, "ok": False, "error": "no_path_match"})
            all_ok = False
            continue
        pm = path_masks[pi]
        eiou = iou(ref_m, pm)
        cb = mask_to_viewbox_bbox(pm)
        cd = centroid_distance(elem.centroid, cb.centroid)
        ok = eiou >= min_element_iou and cd <= max_centroid_delta
        if not ok:
            all_ok = False
        per_element.append(
            {
                "id": elem.id,
                "label": elem.label,
                "path_index": pi,
                "iou": round(eiou, 4),
                "centroid_delta": round(cd, 3),
                "bbox": cb.to_dict(),
                "ref_bbox": elem.bbox.to_dict(),
                "ok": ok,
            }
        )

    return {
        "ok": all_ok and overall_iou >= min_overall_iou,
        "overall_iou": round(overall_iou, 4),
        "path_map": path_map,
        "elements": per_element,
        "candidate_path_count": len(paths),
    }


def load_reference_elements(path: Path) -> list[ElementMap]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return [ElementMap.from_dict(e) for e in data["elements"]]


def load_path_index_map(path: Path, svg_name: str = "logo-mark.svg") -> dict[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    raw = data.get(svg_name, {})
    return {str(k): v for k, v in raw.items()}


def embed_labels_union(
    ref_by_label: dict[str, ElementMap],
    labels: list[str],
    shape: tuple[int, int],
) -> np.ndarray:
    full = np.zeros(shape, dtype=bool)
    for label in labels:
        elem = ref_by_label.get(label)
        if elem is None:
            continue
        full |= embed_element_mask(elem, shape)
    return full


def compare_by_path_map(
    candidate_svg: Path | str,
    reference_json: Path | str,
    path_index_json: Path | str,
    *,
    render_size: int = 256,
    svg_name: str = "logo-mark.svg",
) -> dict[str, Any]:
    """Compare each SVG path index to the reference element with the mapped label."""
    reference = load_reference_elements(Path(reference_json))
    ref_by_label = {e.label: e for e in reference}
    map_data = json.loads(Path(path_index_json).read_text(encoding="utf-8"))
    index_map = load_path_index_map(Path(path_index_json), svg_name)
    compare_union: dict[str, list[str]] = map_data.get("compare_as_union", {})
    mapped_labels = set(index_map.values())

    svg_text = Path(candidate_svg).read_text(encoding="utf-8") if isinstance(candidate_svg, Path) else candidate_svg
    paths = parse_paths(svg_text)
    path_masks = rasterize_paths(svg_text, size=render_size)
    shape = path_masks[0].shape

    defs = extract_defs(svg_text)
    body_paths = "\n".join(f'  <path fill="url(#g)" d="{p.d}"/>' for p in paths)
    full_svg = f'<svg xmlns="{SVG_NS}" viewBox="0 0 100 100">{defs}<rect width="100" height="100" fill="#000"/>{body_paths}</svg>'
    full_mask = render_svg_to_mask(full_svg, size=render_size)
    ref_union = np.zeros(shape, dtype=bool)
    for e in reference:
        if e.label not in mapped_labels and e.label not in map_data.get("reference_only", {}):
            continue
        if e.label in map_data.get("reference_only", {}):
            continue
        ref_union |= embed_element_mask(e, shape)

    rows: list[dict[str, Any]] = []
    for idx_str, label in sorted(index_map.items(), key=lambda x: int(x[0])):
        pi = int(idx_str)
        elem = ref_by_label.get(label)
        if elem is None:
            rows.append({"path_index": pi, "label": label, "ok": False, "error": "no_reference_element"})
            continue
        if pi >= len(path_masks):
            rows.append({"path_index": pi, "label": label, "ok": False, "error": "path_index_out_of_range"})
            continue
        union_labels = compare_union.get(label, [label])
        ref_m = (
            embed_labels_union(ref_by_label, union_labels, shape)
            if len(union_labels) > 1
            else embed_element_mask(elem, shape)
        )
        pm = path_masks[pi]
        eiou = iou(ref_m, pm)
        cb = mask_to_viewbox_bbox(pm)
        cd = centroid_distance(elem.centroid, cb.centroid)
        bi = bbox_iou(elem.bbox, cb)
        rows.append(
            {
                "path_index": pi,
                "label": label,
                "iou": round(eiou, 4),
                "bbox_iou": round(bi, 4),
                "centroid_delta": round(cd, 3),
                "bbox": cb.to_dict(),
                "ref_bbox": elem.bbox.to_dict(),
                "ref_centroid": {"x": elem.centroid[0], "y": elem.centroid[1]},
            }
        )

    return {
        "overall_iou": round(iou(ref_union, full_mask), 4),
        "path_count": len(paths),
        "elements": rows,
    }
