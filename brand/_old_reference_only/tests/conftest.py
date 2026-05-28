from __future__ import annotations

from pathlib import Path

import pytest

BRAND = Path(__file__).resolve().parents[1]
REFERENCE_JSON = BRAND / "reference" / "elements.json"
LOGO_MARK = BRAND / "logo-mark.svg"
REFERENCE_PNG = BRAND / "ChatGPT Image May 16, 2026, 07_58_23 PM.png"


@pytest.fixture(scope="session")
def brand_dir() -> Path:
    return BRAND


@pytest.fixture(scope="session")
def reference_json(brand_dir: Path) -> Path:
    return brand_dir / "reference" / "elements.json"


@pytest.fixture(scope="session")
def logo_mark_svg(brand_dir: Path) -> Path:
    return brand_dir / "logo-mark.svg"
