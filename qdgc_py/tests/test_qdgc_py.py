from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

from qdgc_py import decode_bounds, decode_centroid, encode, encode_many


def _load_legacy_module():
    repo_root = Path(__file__).resolve().parents[2]
    legacy_path = repo_root / "qdgc_py_legacy" / "tools" / "qdgc_lib.py"
    spec = importlib.util.spec_from_file_location("legacy_qdgc_lib", legacy_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    "lon,lat,level",
    [
        (38.98754324, -9.87548764, 5),
        (-12.25, 34.75, 4),
        (0.0, 0.0, 6),
        (179.999, -89.999, 3),
        (-179.999, 89.999, 2),
    ],
)
def test_encode_matches_legacy(lon: float, lat: float, level: int):
    legacy = _load_legacy_module()
    assert encode(lon, lat, level) == legacy.qdgc(lon, lat, level)


def test_encode_many_order():
    points = [(10.1, 59.9), (11.0, 60.0), (12.3, 61.2)]
    single = [encode(lon, lat, 4) for lon, lat in points]
    assert encode_many(points, 4) == single


def test_decode_bounds_contains_original_point():
    lon, lat, level = 38.98754324, -9.87548764, 5
    code = encode(lon, lat, level)
    cell = decode_bounds(code)
    assert cell.min_lon <= lon <= cell.max_lon
    assert cell.min_lat <= lat <= cell.max_lat


def test_decode_centroid_in_bounds():
    code = encode(12.34, 56.78, 7)
    cell = decode_bounds(code)
    c_lon, c_lat = decode_centroid(code)
    assert cell.min_lon <= c_lon <= cell.max_lon
    assert cell.min_lat <= c_lat <= cell.max_lat


def test_invalid_code_raises():
    with pytest.raises(ValueError):
        decode_bounds("not-a-qdgc")
