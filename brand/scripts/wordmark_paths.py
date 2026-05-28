"""Generate outlined wordmark path for logo-lockup-horizontal.svg."""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONT_URL = "https://cdn.jsdelivr.net/fontsource/fonts/inter@latest/latin-600-normal.ttf"
TEXT = "Novolis"
FONT_SIZE = 14
MARK_WIDTH = 24
GAP = 4
PADDING = 1


def fetch_font(dest: Path) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        urllib.request.urlretrieve(FONT_URL, dest)
    return dest


def build_wordmark(font_path: Path) -> dict:
    font = TTFont(font_path)
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    scale = FONT_SIZE / upm
    asc = font["hhea"].ascent * scale
    desc = abs(font["hhea"].descent) * scale
    text_h = asc + desc
    y_offset = (24 - text_h) / 2 + asc

    paths: list[str] = []
    x = 0.0
    for ch in TEXT:
        glyph_name = cmap[ord(ch)]
        pen = SVGPathPen(glyph_set)
        tpen = TransformPen(
            pen,
            Transform(scale, 0, 0, -scale, MARK_WIDTH + GAP + x, y_offset),
        )
        glyph_set[glyph_name].draw(tpen)
        paths.append(pen.getCommands())
        x += font["hmtx"].metrics[glyph_name][0] * scale

    total_w = MARK_WIDTH + GAP + x + PADDING
    return {"path": " ".join(paths), "viewBoxWidth": round(total_w, 2)}


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    font_path = fetch_font(root / ".cache" / "Inter-SemiBold.ttf")
    print(json.dumps(build_wordmark(font_path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
