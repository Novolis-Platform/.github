#!/usr/bin/env python3
"""Merge bootstrap shape-points into spec/logo-graph.json (keeps params/topology)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
BRAND = SCRIPTS.parent
GRAPH = BRAND / "spec" / "logo-graph.json"
BOOT = BRAND / "reference" / "shape-points.json"

sys.path.insert(0, str(SCRIPTS))
from shape_points import extract_shape_points, star_tips  # noqa: E402
from path_tools import load_reference_elements  # noqa: E402


def _bootstrap_to_layer(shape: dict, graph_layer: dict) -> dict:
    layer = dict(graph_layer)
    layer["nodes"] = [{"id": p["role"], "x": p["x"], "y": p["y"]} for p in shape["points"]]
    if "apex" in shape:
        layer["apex"] = shape["apex"]
    return layer


def main() -> None:
    if not GRAPH.exists():
        raise SystemExit(f"Missing {GRAPH}")

    graph = json.loads(GRAPH.read_text(encoding="utf-8"))
    bootstrap = extract_shape_points()
    BOOT.write_text(json.dumps(bootstrap, indent=2), encoding="utf-8")

    by_label = {s["label"]: s for s in bootstrap["shapes"]}
    layers = []
    for layer in graph["layers"]:
        lid = layer["id"]
        if lid in by_label:
            layers.append(_bootstrap_to_layer(by_label[lid], layer))
        else:
            layers.append(layer)

    # refresh star from analytic tips
    elems = load_reference_elements(BRAND / "reference" / "elements.json")
    star = next(e for e in elems if e.label == "star")
    tips = star_tips(star)
    for i, layer in enumerate(layers):
        if layer["id"] == "star":
            layers[i] = {
                **layer,
                "nodes": [
                    {"id": r, "x": round(tips[j][0], 2), "y": round(tips[j][1], 2)}
                    for j, r in enumerate(["tip_n", "tip_e", "tip_s", "tip_w"])
                ],
            }

    graph["layers"] = layers
    GRAPH.write_text(json.dumps(graph, indent=2), encoding="utf-8")
    print(f"Updated {GRAPH} from bootstrap ({len(layers)} layers)")


if __name__ == "__main__":
    main()
