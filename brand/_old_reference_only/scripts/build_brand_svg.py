"""Regenerate logo-lockup-horizontal.svg from logo-mark.svg + outlined wordmark."""
from __future__ import annotations

import re
from pathlib import Path

from fontTools.misc.transform import Transform
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from wordmark_paths import fetch_font

BOLD_URL = "https://cdn.jsdelivr.net/fontsource/fonts/inter@latest/latin-700-normal.ttf"


def fetch_bold(dest: Path) -> TTFont:
    import urllib.request

    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        urllib.request.urlretrieve(BOLD_URL, dest)
    return TTFont(dest)


def outline_text(font: TTFont, text: str, size: float, x: float, y: float) -> tuple[str, float]:
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    parts: list[str] = []
    pen_x = 0.0
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyph_set)
        tpen = TransformPen(
            pen,
            Transform(scale, 0, 0, -scale, x + pen_x, y),
        )
        glyph_set[name].draw(tpen)
        parts.append(pen.getCommands())
        pen_x += font["hmtx"].metrics[name][0] * scale
    return " ".join(parts), pen_x


def extract_icon(svg: str) -> tuple[str, str]:
    defs = re.search(r"<defs>(.*?)</defs>", svg, re.S)
    body = re.sub(r"<defs>.*?</defs>", "", svg, flags=re.S)
    body = re.sub(r"^<svg[^>]*>|</svg>\s*$", "", body, flags=re.S).strip()
    return (defs.group(1).strip() if defs else ""), body


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    icon_defs, icon_body = extract_icon((root / "logo-mark.svg").read_text(encoding="utf-8"))
    font = fetch_bold(root / ".cache" / "Inter-Bold.ttf")
    word, ww = outline_text(font, "Novolis", 26, 0, 0)
    word, _ = outline_text(font, "Novolis", 26, 96, 68)
    w = int(96 + ww + 16)
    defs = f"  <defs>\n    {icon_defs}\n  </defs>\n" if icon_defs else ""
    lock = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} 100" role="img" aria-label="Novolis">
{defs.rstrip()}
  <g transform="translate(6 8) scale(0.84)">
    {icon_body}
  </g>
  <path fill="currentColor" d="{word}"/>
</svg>
'''
    (root / "logo-lockup-horizontal.svg").write_text(lock, encoding="utf-8")
    print(f"Wrote logo-lockup-horizontal.svg ({w}x100)")


if __name__ == "__main__":
    main()
