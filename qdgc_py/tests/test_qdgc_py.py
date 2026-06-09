from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

from qdgc_py import (
    bbox_to_cells,
    cell_to_boundary,
    cell_to_children,
    cell_to_parent,
    decode_bounds,
    decode_centroid,
    encode,
    encode_many,
    estimate_cell_count,
    is_valid_cell,
    level_degrees,
    polygon_to_cells,
)


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


def test_cell_to_boundary_contains_encoded_point():
    lon, lat, level = 12.34, 56.78, 5
    code = encode(lon, lat, level)
    boundary_latlon = cell_to_boundary(code)
    lats = [p[0] for p in boundary_latlon]
    lons = [p[1] for p in boundary_latlon]

    assert boundary_latlon[0] == boundary_latlon[-1]
    assert min(lons) <= lon <= max(lons)
    assert min(lats) <= lat <= max(lats)


def test_polygon_to_cells_box_expected_count_level2():
    exterior = [
        (10.0, 20.0),
        (12.0, 20.0),
        (12.0, 22.0),
        (10.0, 22.0),
        (10.0, 20.0),
    ]
    cells = polygon_to_cells(exterior, 2, predicate="centroid")
    assert len(cells) == 64


def test_bbox_to_cells_expected_count_level2():
    cells = bbox_to_cells(10.0, 20.0, 12.0, 22.0, 2)
    assert len(cells) == 64


def test_parent_children_consistency():
    code = encode(10.1, -2.2, 4)
    parent = cell_to_parent(code, 2)
    children = cell_to_children(parent, 4)

    assert code in children
    assert len(children) == 16
    assert cell_to_parent(code) == code[:-1]


def test_antimeridian_polygon_and_bbox_fill():
    exterior = [
        (179.0, -1.0),
        (-179.0, -1.0),
        (-179.0, 1.0),
        (179.0, 1.0),
        (179.0, -1.0),
    ]
    poly_cells = polygon_to_cells(exterior, 2, predicate="centroid")
    bbox_cells = bbox_to_cells(179.0, -1.0, -179.0, 1.0, 2)

    assert len(poly_cells) == 64
    assert len(bbox_cells) == 64
    assert poly_cells == bbox_cells


def test_polar_fill_does_not_error_and_is_deterministic():
    exterior = [
        (-1.0, 89.0),
        (1.0, 89.0),
        (1.0, 90.0),
        (-1.0, 90.0),
        (-1.0, 89.0),
    ]
    cells = polygon_to_cells(exterior, 2, predicate="centroid")
    assert len(cells) == 32
    assert cells == sorted(cells)


def test_estimate_cell_count_within_five_percent():
    exterior = [
        (10.0, 20.0),
        (12.0, 20.0),
        (12.0, 22.0),
        (10.0, 22.0),
        (10.0, 20.0),
    ]
    actual = len(polygon_to_cells(exterior, 6, predicate="centroid"))
    estimate = estimate_cell_count(exterior, 6)

    assert actual > 0
    assert abs(estimate - actual) / actual <= 0.05


def test_is_valid_cell_and_level_degrees():
    code = encode(-45.5, 12.75, 3)
    assert is_valid_cell(code)
    assert not is_valid_cell("E999N99ZZ")
    assert level_degrees(3) == 0.125
