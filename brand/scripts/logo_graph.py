#!/usr/bin/env python3
"""Load logo-graph.json and emit SVG path data (deterministic reconstruction)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

BRAND = Path(__file__).resolve().parent.parent
DEFAULT_GRAPH = BRAND / "spec" / "logo-graph.json"

from shape_points import (  # noqa: E402
    STAR_CONCAVITY,
    _catmull_rom_closed,
    polygon_path,
    star_quadratic_path,
    swirl_crescent_path,
)


def load_graph(path: Path | None = None) -> dict[str, Any]:
    p = path or DEFAULT_GRAPH
    return json.loads(p.read_text(encoding="utf-8"))


def layer_to_shape_record(layer: dict[str, Any]) -> dict[str, Any]:
    """Adapt logo-graph layer to shape_points.path_from_shape_record format."""
    topo = layer["topology"]
    path_map = {
        "swirl_crescent": "swirl_crescent",
        "polygon": "polygon",
        "catmull_closed": "catmull",
        "star_quadratic": "star",
    }
    rec: dict[str, Any] = {
        "label": layer["id"],
        "path": path_map.get(topo, topo),
        "points": [{"id": n["id"], "role": n["id"], "x": n["x"], "y": n["y"]} for n in layer["nodes"]],
    }
    if "apex" in layer:
        rec["apex"] = layer["apex"]
    params = layer.get("params", {})
    rec.update(params)
    return rec


def path_from_layer(layer: dict[str, Any]) -> str:
    rec = layer_to_shape_record(layer)
    topo = layer["topology"]
    pts = [(n["x"], n["y"]) for n in layer["nodes"]]

    if topo == "swirl_crescent":
        ap = layer["apex"]
        p = layer.get("params", {})
        return swirl_crescent_path(
            pts[0],
            pts[1],
            pts[2],
            (ap["x"], ap["y"]),
            outer_pull=float(p.get("outer_pull", 0.88)),
            inner_pull=float(p.get("inner_pull", 0.42)),
        )
    if topo == "polygon":
        return polygon_path(pts)
    if topo == "catmull_closed":
        return _catmull_rom_closed(pts, float(layer.get("params", {}).get("tension", 0.2)))
    if topo == "star_quadratic":
        return star_quadratic_path(pts, concavity=float(layer.get("params", {}).get("concavity", STAR_CONCAVITY)))
    raise ValueError(f"unknown topology {topo!r}")


def build_svg(graph: dict[str, Any] | None = None) -> str:
    g = graph or load_graph()
    grad = g["gradient"]
    stops = "\n".join(
        f'      <stop offset="{s["offset"]}" stop-color="{s["color"]}"/>'
        for s in grad["stops"]
    )
    paths: list[str] = []
    by_id = {layer["id"]: layer for layer in g["layers"]}
    for lid in g["build_order"]:
        layer = by_id[lid]
        d = path_from_layer(layer)
        paths.append(f'  <path fill="url(#{grad["id"]})" d="{d}"/>')

    body = "\n".join(paths)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Novolis">
  <defs>
    <linearGradient id="{grad["id"]}" x1="{grad["x1"]}" y1="{grad["y1"]}" x2="{grad["x2"]}" y2="{grad["y2"]}" gradientUnits="userSpaceOnUse">
{stops}
    </linearGradient>
  </defs>
{body}
</svg>
"""


def graph_to_bootstrap_shapes(graph: dict[str, Any]) -> list[dict[str, Any]]:
    """Convert graph layers to shape-points.json-compatible shape list."""
    out: list[dict[str, Any]] = []
    for layer in graph["layers"]:
        rec = layer_to_shape_record(layer)
        rec["point_count"] = len(rec["points"])
        rec["source"] = "spec/logo-graph.json"
        out.append(rec)
    return out
