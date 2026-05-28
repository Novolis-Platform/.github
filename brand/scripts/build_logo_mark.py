#!/usr/bin/env python3
"""Generate logo-mark.svg from the deterministic logo graph."""
from __future__ import annotations

import json
from pathlib import Path

BRAND = Path(__file__).resolve().parent.parent
OUT = BRAND / "logo-mark.svg"
GRAPH = BRAND / "spec" / "logo-graph.json"


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


def _node_xy(node: dict) -> tuple[float, float]:
    return (float(node["x"]), float(node["y"]))


def _format_path(points: list[tuple[float, float]]) -> str:
    parts = [f"M{points[0][0]:.2f},{points[0][1]:.2f}"]
    for x, y in points[1:]:
        parts.append(f"L{x:.2f},{y:.2f}")
    return "".join(parts) + "Z"


def _swirl_crescent(layer: dict) -> str:
    nodes = {_["id"]: _node_xy(_) for _ in layer["nodes"]}
    lo = nodes["left_outer"]
    li = nodes["left_inner"]
    rt = nodes["right_tip"]
    ap = _node_xy(layer["apex"])
    params = layer.get("params", {})
    outer_pull = float(params.get("outer_pull", 0.74))
    inner_pull = float(params.get("inner_pull", 0.58))

    c1x = lo[0] + (ap[0] - lo[0]) * outer_pull
    c1y = lo[1] + (ap[1] - lo[1]) * outer_pull
    c2x = rt[0] + (ap[0] - rt[0]) * outer_pull
    c2y = rt[1] + (ap[1] - rt[1]) * outer_pull
    qx = rt[0] + (li[0] - rt[0]) * inner_pull
    qy = rt[1] + (li[1] - rt[1]) * inner_pull
    return (
        f"M{lo[0]:.2f},{lo[1]:.2f}"
        f"C{c1x:.2f},{c1y:.2f} {c2x:.2f},{c2y:.2f} {rt[0]:.2f},{rt[1]:.2f}"
        f"Q{qx:.2f},{qy:.2f} {li[0]:.2f},{li[1]:.2f}Z"
    )


def _arc_crescent(layer: dict) -> str:
    nodes = {_["id"]: _node_xy(_) for _ in layer["nodes"]}
    lo = nodes["left_outer"]
    ro = nodes["right_outer"]
    ri = nodes["right_inner"]
    li = nodes["left_inner"]
    ap = _node_xy(layer["apex"])
    inner_ap = _node_xy(layer["inner_apex"])
    params = layer.get("params", {})
    outer_pull = float(params.get("outer_pull", 0.82))
    inner_pull = float(params.get("inner_pull", 0.72))

    oc1x = lo[0] + (ap[0] - lo[0]) * outer_pull
    oc1y = lo[1] + (ap[1] - lo[1]) * outer_pull
    oc2x = ro[0] + (ap[0] - ro[0]) * outer_pull
    oc2y = ro[1] + (ap[1] - ro[1]) * outer_pull
    ic1x = ri[0] + (inner_ap[0] - ri[0]) * inner_pull
    ic1y = ri[1] + (inner_ap[1] - ri[1]) * inner_pull
    ic2x = li[0] + (inner_ap[0] - li[0]) * inner_pull
    ic2y = li[1] + (inner_ap[1] - li[1]) * inner_pull
    return (
        f"M{lo[0]:.2f},{lo[1]:.2f}"
        f"C{oc1x:.2f},{oc1y:.2f} {oc2x:.2f},{oc2y:.2f} {ro[0]:.2f},{ro[1]:.2f}"
        f"L{ri[0]:.2f},{ri[1]:.2f}"
        f"C{ic1x:.2f},{ic1y:.2f} {ic2x:.2f},{ic2y:.2f} {li[0]:.2f},{li[1]:.2f}Z"
    )


def _star_path(layer: dict) -> str:
    tips = [_node_xy(n) for n in layer["nodes"]]
    params = layer.get("params", {})
    concavity = float(params.get("concavity", 0.248))
    cx = sum(p[0] for p in tips) / len(tips)
    cy = sum(p[1] for p in tips) / len(tips)
    parts = [f"M{tips[0][0]:.2f},{tips[0][1]:.2f}"]
    for i in range(4):
        x0, y0 = tips[i]
        x1, y1 = tips[(i + 1) % 4]
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        qx = cx + (mx - cx) * concavity
        qy = cy + (my - cy) * concavity
        parts.append(f"Q{qx:.2f},{qy:.2f} {x1:.2f},{y1:.2f}")
    return "".join(parts) + "Z"


def path_for_layer(layer: dict) -> str:
    topology = layer["topology"]
    if topology == "arc_crescent":
        return _arc_crescent(layer)
    if topology == "swirl_crescent":
        return _swirl_crescent(layer)
    if topology == "polygon":
        return _format_path([_node_xy(n) for n in layer["nodes"]])
    if topology == "catmull_closed":
        points = [_node_xy(n) for n in layer["nodes"]]
        return _catmull_rom_closed(points, float(layer.get("params", {}).get("tension", 0.04)))
    if topology == "star_quadratic":
        return _star_path(layer)
    raise ValueError(f"unknown topology {topology!r}")


def build() -> str:
    graph = json.loads(GRAPH.read_text(encoding="utf-8"))
    by_id = {layer["id"]: layer for layer in graph["layers"]}
    paths = [path_for_layer(by_id[layer_id]) for layer_id in graph["build_order"]]
    gradient = graph["gradient"]
    stops = "\n".join(
        f'      <stop offset="{stop["offset"]}" stop-color="{stop["color"]}"/>'
        for stop in gradient["stops"]
    )

    body = "\n".join(f'  <path fill="url(#g)" d="{d}"/>' for d in paths)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Novolis">
  <defs>
    <linearGradient id="{gradient["id"]}" x1="{gradient["x1"]}" y1="{gradient["y1"]}" x2="{gradient["x2"]}" y2="{gradient["y2"]}" gradientUnits="userSpaceOnUse">
{stops}
    </linearGradient>
  </defs>
{body}
</svg>
"""


def main() -> None:
    if not GRAPH.exists():
        raise SystemExit(f"Missing logo graph: {GRAPH}")
    OUT.write_text(build(), encoding="utf-8", newline="\n")
    print(f"Wrote {OUT} ({GRAPH.relative_to(BRAND)} -> {OUT.name})")


if __name__ == "__main__":
    main()
