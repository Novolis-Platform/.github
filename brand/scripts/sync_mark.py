#!/usr/bin/env python3
"""Copy logo-mark.svg geometry into favicon, mono-dark, and logo-brand."""
from pathlib import Path
import re

BRAND = Path(__file__).resolve().parent.parent
mark = (BRAND / "logo-mark.svg").read_text(encoding="utf-8")
(BRAND / "favicon.svg").write_text(mark, encoding="utf-8")
(BRAND / "logo-mark-mono-dark.svg").write_text(mark, encoding="utf-8")

body = mark.split("</defs>", 1)[1].strip().removesuffix("</svg>").strip()
indented = "\n    ".join(body.splitlines())
new_g = f'  <g transform="translate(46 36) scale(4.2)">\n    {indented}\n  </g>'

mark_defs = re.search(r"<defs>(.*?)</defs>", mark, re.S)
defs_block = mark_defs.group(1).strip() if mark_defs else ""

brand_path = BRAND / "logo-brand.svg"
brand = brand_path.read_text(encoding="utf-8")
brand = re.sub(r"<defs>.*?</defs>", f"<defs>\n    {defs_block}\n    <linearGradient id=\"novolis-tagline\" x1=\"64\" y1=\"0\" x2=\"448\" y2=\"0\" gradientUnits=\"userSpaceOnUse\">\n      <stop offset=\"0\" stop-color=\"#22d3ee\"/>\n      <stop offset=\"1\" stop-color=\"#a855f7\"/>\n    </linearGradient>\n  </defs>", brand, count=1, flags=re.S)
brand = re.sub(
    r'  <g transform="translate\(46 36\) scale\(4\.2\)">.*?</g>',
    new_g,
    brand,
    count=1,
    flags=re.S,
)
brand_path.write_text(brand, encoding="utf-8")
print("Synced mark -> favicon, logo-mark-mono-dark, logo-brand")
