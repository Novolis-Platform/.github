#!/usr/bin/env python3
"""
Compare a candidate logo-mark SVG against reference/elements.json.

Usage:
  python logo_match.py
  python logo_match.py --svg ../logo-mark.svg --json ../reference/elements.json
  python logo_match.py --report report.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from path_tools import compare_by_path_map, compare_to_reference

BRAND = Path(__file__).resolve().parent.parent
DEFAULT_SVG = BRAND / "logo-mark.svg"
DEFAULT_REF = BRAND / "reference" / "elements.json"
DEFAULT_PATH_MAP = BRAND / "reference" / "path-index-map.json"


def main() -> int:
    p = argparse.ArgumentParser(description="Match candidate SVG paths to reference elements")
    p.add_argument("--svg", type=Path, default=DEFAULT_SVG)
    p.add_argument("--json", type=Path, default=DEFAULT_REF)
    p.add_argument("--report", type=Path, help="Write JSON report to file")
    p.add_argument("--min-element-iou", type=float, default=0.45)
    p.add_argument("--max-centroid-delta", type=float, default=6.0)
    p.add_argument("--min-overall-iou", type=float, default=0.55)
    p.add_argument("--path-map", type=Path, default=DEFAULT_PATH_MAP)
    p.add_argument(
        "--by-path-map",
        action="store_true",
        help="Compare using reference/path-index-map.json (recommended)",
    )
    p.add_argument("--fail", action="store_true", help="Exit 1 if match fails")
    args = p.parse_args()

    if not args.json.exists():
        print(f"Missing reference: {args.json}\nRun: python reference_mask.py extract", file=sys.stderr)
        return 2

    if args.by_path_map:
        if not args.path_map.exists():
            print(f"Missing path map: {args.path_map}", file=sys.stderr)
            return 2
        report = compare_by_path_map(args.svg, args.json, args.path_map)
        if args.fail:
            return 0  # path-map mode is diagnostic unless thresholds added
    else:
        report = compare_to_reference(
            args.svg,
            args.json,
            min_element_iou=args.min_element_iou,
            max_centroid_delta=args.max_centroid_delta,
            min_overall_iou=args.min_overall_iou,
        )
    text = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.write_text(text, encoding="utf-8")
        print(f"Wrote {args.report}")
    else:
        print(text)

    if args.fail and not report["ok"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
