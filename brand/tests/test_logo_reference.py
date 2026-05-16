"""Verify logo-mark.svg against reference mask coordinate map."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

BRAND = Path(__file__).resolve().parents[1]
SCRIPTS = BRAND / "scripts"
REFERENCE_DIR = BRAND / "reference"
BASELINE = REFERENCE_DIR / "baselines" / "logo-mark.json"


def _ensure_reference() -> None:
    if (REFERENCE_DIR / "elements.json").exists():
        return
    subprocess.run(
        [sys.executable, str(SCRIPTS / "reference_mask.py"), "extract"],
        cwd=SCRIPTS,
        check=True,
    )


@pytest.fixture(scope="module", autouse=True)
def reference_artifacts() -> None:
    _ensure_reference()


@pytest.fixture(scope="module")
def path_tools():
    sys.path.insert(0, str(SCRIPTS))
    import path_tools as pt

    return pt


def test_reference_files_exist() -> None:
    assert (REFERENCE_DIR / "mask.png").is_file()
    assert (REFERENCE_DIR / "elements.json").is_file()
    assert (REFERENCE_DIR / "path-index-map.json").is_file()
    assert (REFERENCE_DIR / "COORDINATE_MAP.md").is_file()


def test_reference_has_core_labels() -> None:
    data = json.loads((REFERENCE_DIR / "elements.json").read_text(encoding="utf-8"))
    labels = {e["label"] for e in data["elements"]}
    for name in ("swirl_upper", "swirl_lower", "n_diagonal", "star"):
        assert name in labels, f"missing reference label {name}"


def test_path_index_map_has_six_paths() -> None:
    data = json.loads((REFERENCE_DIR / "path-index-map.json").read_text(encoding="utf-8"))
    m = data["logo-mark.svg"]
    assert len(m) == 6
    assert m["0"] == "swirl_upper"
    assert m["5"] == "star"


def test_parse_logo_mark_paths(path_tools, logo_mark_svg: Path) -> None:
    paths = path_tools.parse_paths(logo_mark_svg.read_text(encoding="utf-8"))
    assert len(paths) == 6


def test_compare_by_path_map_runs(path_tools, logo_mark_svg: Path, reference_json: Path) -> None:
    report = path_tools.compare_by_path_map(
        logo_mark_svg,
        reference_json,
        REFERENCE_DIR / "path-index-map.json",
    )
    assert report["path_count"] == 6
    assert len(report["elements"]) == 6
    assert "overall_iou" in report


@pytest.mark.parametrize(
    "path_index,label,min_iou,max_centroid",
    [
        (0, "swirl_upper", 0.58, 5.0),
        (1, "swirl_lower", 0.70, 5.0),
        (2, "n_right_stem", 0.70, 3.0),
        (3, "n_left_stem", 0.68, 3.0),
        (4, "n_diagonal", 0.68, 5.0),
        (5, "star", 0.78, 2.0),
    ],
)
def test_element_match_by_path_index(
    path_tools,
    logo_mark_svg: Path,
    reference_json: Path,
    path_index: int,
    label: str,
    min_iou: float,
    max_centroid: float,
) -> None:
    report = path_tools.compare_by_path_map(
        logo_mark_svg,
        reference_json,
        REFERENCE_DIR / "path-index-map.json",
    )
    row = next(r for r in report["elements"] if r["path_index"] == path_index)
    if "error" in row:
        pytest.skip(row["error"])
    assert row["label"] == label
    assert row["iou"] >= min_iou, f"{label} IoU {row['iou']}"
    assert row["centroid_delta"] <= max_centroid, (
        f"path {path_index} ({label}) centroid delta {row['centroid_delta']}"
    )


def test_overall_silhouette_iou(path_tools, logo_mark_svg: Path, reference_json: Path) -> None:
    report = path_tools.compare_by_path_map(
        logo_mark_svg,
        reference_json,
        REFERENCE_DIR / "path-index-map.json",
    )
    assert report["overall_iou"] >= 0.72, f"overall IoU {report['overall_iou']}"


def test_regression_baseline(path_tools, logo_mark_svg: Path, reference_json: Path) -> None:
    """Scores must not regress vs committed baseline (run logo_match --by-path-map to refresh)."""
    report = path_tools.compare_by_path_map(
        logo_mark_svg,
        reference_json,
        REFERENCE_DIR / "path-index-map.json",
    )
    if not BASELINE.exists():
        BASELINE.parent.mkdir(parents=True, exist_ok=True)
        BASELINE.write_text(json.dumps(report, indent=2), encoding="utf-8")
        pytest.skip("wrote initial baseline")
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    assert report["overall_iou"] >= baseline["overall_iou"] * 0.92
    base_by = {(r["path_index"], r["label"]): r for r in baseline["elements"] if "iou" in r}
    for row in report["elements"]:
        if "error" in row:
            continue
        key = (row["path_index"], row["label"])
        if key not in base_by:
            continue
        assert row["iou"] >= base_by[key]["iou"] * 0.90, f"regression on {row['label']}"
