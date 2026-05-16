"""Write logo-lockup-horizontal.svg from mark + Inter wordmark outlines."""
from __future__ import annotations

from pathlib import Path

from wordmark_paths import build_wordmark, fetch_font

MARK_PATHS = [
    "M6 4h4a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
    "M14 4h4a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
    "M6 12h4a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2z",
    "M15 13h4a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2z",
]


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    font_path = fetch_font(root / ".cache" / "Inter-SemiBold.ttf")
    wm = build_wordmark(font_path)
    w = int(wm["viewBoxWidth"] + 0.5)

    mark = "\n  ".join(f'<path fill="currentColor" d="{d}"/>' for d in MARK_PATHS)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} 24" role="img" aria-label="Novolis">
  {mark}
  <path fill="currentColor" d="{wm["path"]}"/>
</svg>
'''
    (root / "logo-lockup-horizontal.svg").write_text(svg, encoding="utf-8")
    print(f"Wrote logo-lockup-horizontal.svg ({len(svg)} bytes)")


if __name__ == "__main__":
    main()
