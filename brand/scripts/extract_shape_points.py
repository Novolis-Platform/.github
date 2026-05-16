#!/usr/bin/env python3
"""Bootstrap node proposals from per-shape masks (NOT source of truth).

Writes reference/shape-points.json and debug PNGs. Merge into spec/logo-graph.json manually.
See brand/LOGO_VECTOR_SPEC.md.
"""
from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from shape_points import render_points_overlay, write_shape_points  # noqa: E402


def main() -> None:
    data = write_shape_points()
    overlay = render_points_overlay(data)
    print(f"Wrote {SCRIPTS.parent / 'reference' / 'shape-points.json'} ({len(data['shapes'])} shapes)")
    for s in data["shapes"]:
        print(f"  {s['label']}: {s['point_count']} points ({s['source']})")
    print(f"Wrote {overlay}")


if __name__ == "__main__":
    main()
