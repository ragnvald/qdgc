"""Core helpers for Extended QDGC.

QDGC uses degree-based square cells in EPSG:4326.

- Level 0 is 1 degree x 1 degree.
- Each level subdivides by 2 in each axis, so side length in degrees is
    ``1.0 / (2 ** level)``.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
import re
from itertools import product
from typing import Iterable, Sequence


_CODE_RE = re.compile(r"^(?P<lon_hem>[EW])(?P<lon_deg>\d{3})(?P<lat_hem>[NS])(?P<lat_deg>\d{2})(?P<path>[ABCD]*)$")

_EARTH_RADIUS_KM = 6371.0088
_EPS = 1e-12


@dataclass(frozen=True)
class QDGCCell:
    """Decoded QDGC cell information."""

    code: str
    level: int
    min_lon: float
    min_lat: float
    max_lon: float
    max_lat: float

    @property
    def centroid(self) -> tuple[float, float]:
        return ((self.min_lon + self.max_lon) / 2.0, (self.min_lat + self.max_lat) / 2.0)


def _validate_level(level: int) -> int:
    try:
        value = int(level)
    except Exception as exc:
        raise ValueError("level must be an integer") from exc
    if value < 0:
        raise ValueError("level must be >= 0")
    return value


def _normalize_fraction(value: float) -> float:
    # Keep legacy behavior exactly: only strip integer parts when |value| > 1.
    if value > 1:
        return value - math.floor(value)
    if value < -1:
        return value + abs(math.ceil(value))
    return value


def _lonlat_prefix(lon: float, lat: float) -> str:
    lon_prefix = "W" if lon < 0 else "E"
    lat_prefix = "S" if lat < 0 else "N"
    lon_deg = str(int(abs(lon))).zfill(3)
    lat_deg = str(int(abs(lat))).zfill(2)
    return f"{lon_prefix}{lon_deg}{lat_prefix}{lat_deg}"


def _step(lon_value: float, lat_value: float) -> tuple[str, float, float]:
    # Quadrant rules are preserved from legacy qdgc_lib implementation.
    if (lon_value >= 0) and (lat_value >= 0):
        if (lon_value < 0.5) and (lat_value >= 0.5):
            return "A", lon_value * 2, (lat_value - 0.5) * 2
        if (lon_value >= 0.5) and (lat_value >= 0.5):
            return "B", (lon_value - 0.5) * 2, (lat_value - 0.5) * 2
        if (lon_value < 0.5) and (lat_value < 0.5):
            return "C", lon_value * 2, lat_value * 2
        return "D", (lon_value - 0.5) * 2, lat_value * 2

    if (lon_value >= 0) and (lat_value <= 0):
        if (lon_value < 0.5) and (lat_value > -0.5):
            return "A", lon_value * 2, lat_value * 2
        if (lon_value >= 0.5) and (lat_value > -0.5):
            return "B", (lon_value - 0.5) * 2, lat_value * 2
        if (lon_value < 0.5) and (lat_value <= -0.5):
            return "C", lon_value * 2, (lat_value + 0.5) * 2
        return "D", (lon_value - 0.5) * 2, (lat_value + 0.5) * 2

    if (lon_value <= 0) and (lat_value <= 0):
        if (lon_value <= -0.5) and (lat_value > -0.5):
            return "A", (lon_value + 0.5) * 2, lat_value * 2
        if (lon_value > -0.5) and (lat_value > -0.5):
            return "B", lon_value * 2, lat_value * 2
        if (lon_value <= -0.5) and (lat_value <= -0.5):
            return "C", (lon_value + 0.5) * 2, (lat_value + 0.5) * 2
        return "D", lon_value * 2, (lat_value + 0.5) * 2

    if (lon_value <= -0.5) and (lat_value >= 0.5):
        return "A", (lon_value + 0.5) * 2, (lat_value - 0.5) * 2
    if (lon_value > -0.5) and (lat_value >= 0.5):
        return "B", lon_value * 2, (lat_value - 0.5) * 2
    if (lon_value <= -0.5) and (lat_value < 0.5):
        return "C", (lon_value + 0.5) * 2, lat_value * 2
    return "D", lon_value * 2, lat_value * 2


def encode(lon: float, lat: float, level: int) -> str:
    """Encode longitude/latitude to an Extended QDGC code."""

    lon_value = float(lon)
    lat_value = float(lat)
    depth = _validate_level(level)

    prefix = _lonlat_prefix(lon_value, lat_value)
    lon_value = _normalize_fraction(lon_value)
    lat_value = _normalize_fraction(lat_value)

    path_chars: list[str] = []
    while len(path_chars) < depth:
        letter, lon_value, lat_value = _step(lon_value, lat_value)
        path_chars.append(letter)

    return prefix + "".join(path_chars)


def encode_many(points: Iterable[Sequence[float]], level: int) -> list[str]:
    """Encode many points from an iterable of (lon, lat) tuples."""

    depth = _validate_level(level)
    out: list[str] = []
    for point in points:
        if len(point) < 2:
            raise ValueError("each point must provide at least (lon, lat)")
        out.append(encode(float(point[0]), float(point[1]), depth))
    return out


def decode_bounds(code: str) -> QDGCCell:
    """Decode a QDGC code into geographic bounds."""

    m = _CODE_RE.match(str(code).strip())
    if m is None:
        raise ValueError("invalid QDGC code")

    lon_deg = int(m.group("lon_deg"))
    lat_deg = int(m.group("lat_deg"))
    path = m.group("path")

    if m.group("lon_hem") == "E":
        min_lon, max_lon = float(lon_deg), float(lon_deg + 1)
    else:
        min_lon, max_lon = float(-(lon_deg + 1)), float(-lon_deg)

    if m.group("lat_hem") == "N":
        min_lat, max_lat = float(lat_deg), float(lat_deg + 1)
    else:
        min_lat, max_lat = float(-(lat_deg + 1)), float(-lat_deg)

    for c in path:
        mid_lon = (min_lon + max_lon) / 2.0
        mid_lat = (min_lat + max_lat) / 2.0
        if c == "A":
            max_lon = mid_lon
            min_lat = mid_lat
        elif c == "B":
            min_lon = mid_lon
            min_lat = mid_lat
        elif c == "C":
            max_lon = mid_lon
            max_lat = mid_lat
        else:  # D
            min_lon = mid_lon
            max_lat = mid_lat

    return QDGCCell(
        code=m.group(0),
        level=len(path),
        min_lon=min_lon,
        min_lat=min_lat,
        max_lon=max_lon,
        max_lat=max_lat,
    )


def decode_centroid(code: str) -> tuple[float, float]:
    """Return (lon, lat) centroid of a QDGC cell."""

    return decode_bounds(code).centroid


def level_degrees(level: int) -> float:
    """Return QDGC cell side length in degrees for ``level``."""

    return 1.0 / float(2 ** _validate_level(level))


def is_valid_cell(code: str) -> bool:
    """Return True when ``code`` is a syntactically and geographically valid QDGC cell."""

    try:
        cell = decode_bounds(code)
    except ValueError:
        return False
    return (
        -180.0 <= cell.min_lon < cell.max_lon <= 180.0
        and -90.0 <= cell.min_lat < cell.max_lat <= 90.0
    )


def cell_to_boundary(code: str) -> list[tuple[float, float]]:
    """Return closed cell boundary as ``(lat, lon)`` vertices.

    Vertex order is clockwise from the south-west corner.
    """

    cell = decode_bounds(code)
    return [
        (cell.min_lat, cell.min_lon),
        (cell.min_lat, cell.max_lon),
        (cell.max_lat, cell.max_lon),
        (cell.max_lat, cell.min_lon),
        (cell.min_lat, cell.min_lon),
    ]


def cell_to_polygon(code: str) -> list[tuple[float, float]]:
    """Return closed cell boundary as ``(lon, lat)`` vertices (GeoJSON axis order)."""

    return [(lon, lat) for lat, lon in cell_to_boundary(code)]


def cell_to_parent(code: str, parent_level: int | None = None) -> str:
    """Return ancestor cell code at ``parent_level``.

    When ``parent_level`` is None, returns the immediate parent.
    """

    m = _CODE_RE.match(str(code).strip())
    if m is None:
        raise ValueError("invalid QDGC code")
    path = m.group("path")
    level = len(path)

    if parent_level is None:
        if level == 0:
            raise ValueError("level 0 cells do not have a parent")
        target = level - 1
    else:
        target = _validate_level(parent_level)

    if target > level:
        raise ValueError("parent_level must be <= cell level")

    prefix = m.group("lon_hem") + m.group("lon_deg") + m.group("lat_hem") + m.group("lat_deg")
    return prefix + path[:target]


def cell_to_children(code: str, child_level: int | None = None) -> list[str]:
    """Return descendant cell codes at ``child_level``.

    When ``child_level`` is None, returns immediate children.
    """

    m = _CODE_RE.match(str(code).strip())
    if m is None:
        raise ValueError("invalid QDGC code")
    prefix = m.group("lon_hem") + m.group("lon_deg") + m.group("lat_hem") + m.group("lat_deg")
    path = m.group("path")
    level = len(path)

    if child_level is None:
        target = level + 1
    else:
        target = _validate_level(child_level)

    if target < level:
        raise ValueError("child_level must be >= cell level")
    if target == level:
        return [prefix + path]

    depth = target - level
    out: list[str] = []
    for chars in product("ABCD", repeat=depth):
        out.append(prefix + path + "".join(chars))
    return out


def _wrap_lon(lon: float) -> float:
    wrapped = ((float(lon) + 180.0) % 360.0) - 180.0
    if math.isclose(wrapped, -180.0, abs_tol=_EPS):
        return 180.0
    return wrapped


def _unwrap_ring(ring: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    if not ring:
        return []
    out: list[tuple[float, float]] = [(float(ring[0][0]), float(ring[0][1]))]
    for lon, lat in ring[1:]:
        curr = float(lon)
        prev = out[-1][0]
        while curr - prev > 180.0:
            curr -= 360.0
        while curr - prev < -180.0:
            curr += 360.0
        out.append((curr, float(lat)))
    return out


def _ring_bounds(ring: Sequence[tuple[float, float]]) -> tuple[float, float, float, float]:
    lons = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    return (min(lons), min(lats), max(lons), max(lats))


def _close_ring(ring: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    pts = [(float(x), float(y)) for x, y in ring]
    if len(pts) < 3:
        raise ValueError("ring must have at least 3 points")
    if pts[0] != pts[-1]:
        pts.append(pts[0])
    return pts


def _point_on_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> bool:
    cross = (px - ax) * (by - ay) - (py - ay) * (bx - ax)
    if not math.isclose(cross, 0.0, abs_tol=1e-10):
        return False
    if (min(ax, bx) - _EPS) <= px <= (max(ax, bx) + _EPS) and (min(ay, by) - _EPS) <= py <= (max(ay, by) + _EPS):
        return True
    return False


def _point_in_ring(point: tuple[float, float], ring: Sequence[tuple[float, float]]) -> bool:
    x, y = point
    inside = False
    closed = _close_ring(ring)
    for i in range(len(closed) - 1):
        x1, y1 = closed[i]
        x2, y2 = closed[i + 1]
        if _point_on_segment(x, y, x1, y1, x2, y2):
            return True
        intersects = ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / (y2 - y1 + _EPS) + x1)
        if intersects:
            inside = not inside
    return inside


def _point_in_polygon(point: tuple[float, float], exterior: Sequence[tuple[float, float]], holes: Sequence[Sequence[tuple[float, float]]]) -> bool:
    if not _point_in_ring(point, exterior):
        return False
    for hole in holes:
        if _point_in_ring(point, hole):
            return False
    return True


def _orientation(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> int:
    val = (b[1] - a[1]) * (c[0] - b[0]) - (b[0] - a[0]) * (c[1] - b[1])
    if math.isclose(val, 0.0, abs_tol=1e-10):
        return 0
    return 1 if val > 0 else 2


def _segments_intersect(a1: tuple[float, float], a2: tuple[float, float], b1: tuple[float, float], b2: tuple[float, float]) -> bool:
    o1 = _orientation(a1, a2, b1)
    o2 = _orientation(a1, a2, b2)
    o3 = _orientation(b1, b2, a1)
    o4 = _orientation(b1, b2, a2)

    if (o1 != o2) and (o3 != o4):
        return True

    if o1 == 0 and _point_on_segment(b1[0], b1[1], a1[0], a1[1], a2[0], a2[1]):
        return True
    if o2 == 0 and _point_on_segment(b2[0], b2[1], a1[0], a1[1], a2[0], a2[1]):
        return True
    if o3 == 0 and _point_on_segment(a1[0], a1[1], b1[0], b1[1], b2[0], b2[1]):
        return True
    if o4 == 0 and _point_on_segment(a2[0], a2[1], b1[0], b1[1], b2[0], b2[1]):
        return True
    return False


def _rings_intersect(ring_a: Sequence[tuple[float, float]], ring_b: Sequence[tuple[float, float]]) -> bool:
    a = _close_ring(ring_a)
    b = _close_ring(ring_b)
    for i in range(len(a) - 1):
        for j in range(len(b) - 1):
            if _segments_intersect(a[i], a[i + 1], b[j], b[j + 1]):
                return True
    return False


def _cell_polygon_unwrapped(cell: QDGCCell, lon_reference: float) -> list[tuple[float, float]]:
    center = (cell.min_lon + cell.max_lon) / 2.0
    shift = round((lon_reference - center) / 360.0) * 360.0
    min_lon = cell.min_lon + shift
    max_lon = cell.max_lon + shift
    return [
        (min_lon, cell.min_lat),
        (max_lon, cell.min_lat),
        (max_lon, cell.max_lat),
        (min_lon, cell.max_lat),
        (min_lon, cell.min_lat),
    ]


def _bbox_intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] <= b[0] or a[0] >= b[2] or a[3] <= b[1] or a[1] >= b[3])


def _normalize_bbox(min_lon: float, min_lat: float, max_lon: float, max_lat: float) -> tuple[float, float, float, float]:
    a = float(min_lon)
    b = float(min_lat)
    c = float(max_lon)
    d = float(max_lat)
    if b > d:
        b, d = d, b
    b = max(-90.0, b)
    d = min(90.0, d)
    return (a, b, c, d)


def _index_range(min_value: float, max_value: float, origin: float, step: float, size: int) -> tuple[int, int] | None:
    start = int(math.floor((min_value - origin) / step))
    end = int(math.ceil((max_value - origin) / step)) - 1
    start = max(0, start)
    end = min(size - 1, end)
    if end < start:
        return None
    return (start, end)


def bbox_to_cells(min_lon: float, min_lat: float, max_lon: float, max_lat: float, level: int) -> list[str]:
    """Return all level cells that intersect the bbox.

    Input and output use lon/lat order in EPSG:4326. Antimeridian-crossing bboxes
    are supported by passing ``min_lon > max_lon``.
    """

    depth = _validate_level(level)
    min_lon, min_lat, max_lon, max_lat = _normalize_bbox(min_lon, min_lat, max_lon, max_lat)
    if max_lat <= -90.0 or min_lat >= 90.0:
        return []

    step = level_degrees(depth)
    lon_cells = int(round(360.0 / step))
    lat_cells = int(round(180.0 / step))

    lat_range = _index_range(min_lat, max_lat, -90.0, step, lat_cells)
    if lat_range is None:
        return []

    if max_lon - min_lon >= 360.0:
        lon_segments = [(-180.0, 180.0)]
    else:
        min_w = _wrap_lon(min_lon)
        max_w = _wrap_lon(max_lon)
        if min_w <= max_w:
            lon_segments = [(min_w, max_w)]
        else:
            lon_segments = [(min_w, 180.0), (-180.0, max_w)]

    out: list[str] = []
    seen: set[str] = set()
    lat_start, lat_end = lat_range
    for seg_min, seg_max in lon_segments:
        lon_range = _index_range(seg_min, seg_max, -180.0, step, lon_cells)
        if lon_range is None:
            continue
        lon_start, lon_end = lon_range
        for lat_i in range(lat_start, lat_end + 1):
            c_lat = -90.0 + (lat_i + 0.5) * step
            for lon_i in range(lon_start, lon_end + 1):
                c_lon = -180.0 + (lon_i + 0.5) * step
                code = encode(c_lon, c_lat, depth)
                if code not in seen:
                    seen.add(code)
                    out.append(code)

    out.sort()
    return out


def polygon_to_cells(
    exterior: list[tuple[float, float]],
    level: int,
    *,
    holes: list[list[tuple[float, float]]] | None = None,
    predicate: str = "intersects",
) -> list[str]:
    """Return level cells related to the polygon per ``predicate``.

    Input polygon coordinates are in GeoJSON order: ``(lon, lat)``.
    Supported predicates: ``intersects``, ``centroid``, ``contains``.
    """

    if predicate not in {"intersects", "centroid", "contains"}:
        raise ValueError("predicate must be one of: intersects, centroid, contains")

    ext_closed = _close_ring(exterior)
    holes_closed = [_close_ring(h) for h in (holes or [])]

    ext_unwrapped = _unwrap_ring(ext_closed)
    holes_unwrapped = [_unwrap_ring(h) for h in holes_closed]

    min_lon_u, min_lat, max_lon_u, max_lat = _ring_bounds(ext_unwrapped)
    candidate_codes = bbox_to_cells(_wrap_lon(min_lon_u), min_lat, _wrap_lon(max_lon_u), max_lat, level)
    if not candidate_codes:
        return []

    poly_bbox = _ring_bounds(ext_unwrapped)
    lon_ref = (min_lon_u + max_lon_u) / 2.0

    out: list[str] = []
    for code in candidate_codes:
        cell = decode_bounds(code)
        cell_poly = _cell_polygon_unwrapped(cell, lon_ref)
        cell_bbox = _ring_bounds(cell_poly)
        if not _bbox_intersects(poly_bbox, cell_bbox):
            continue

        center = ((cell.min_lon + cell.max_lon) / 2.0, (cell.min_lat + cell.max_lat) / 2.0)
        center_shift = (center[0] + round((lon_ref - center[0]) / 360.0) * 360.0, center[1])
        corners = cell_poly[:-1]

        if predicate == "centroid":
            if _point_in_polygon(center_shift, ext_unwrapped, holes_unwrapped):
                out.append(code)
            continue

        if predicate == "contains":
            if all(_point_in_polygon(corner, ext_unwrapped, holes_unwrapped) for corner in corners):
                out.append(code)
            continue

        # intersects
        if _point_in_polygon(center_shift, ext_unwrapped, holes_unwrapped):
            out.append(code)
            continue
        if any(_point_in_polygon(corner, ext_unwrapped, holes_unwrapped) for corner in corners):
            out.append(code)
            continue
        if any((cell_bbox[0] <= p[0] <= cell_bbox[2] and cell_bbox[1] <= p[1] <= cell_bbox[3]) for p in ext_unwrapped):
            out.append(code)
            continue
        if _rings_intersect(cell_poly, ext_unwrapped):
            out.append(code)
            continue

    out.sort()
    return out


def _area_unit_scale(unit: str) -> float:
    unit_norm = unit.strip().lower()
    if unit_norm == "km^2":
        return 1.0
    if unit_norm == "m^2":
        return 1_000_000.0
    raise ValueError("unit must be 'km^2' or 'm^2'")


def average_cell_area(level: int, *, lat: float | None = None, unit: str = "km^2") -> float:
    """Return approximate cell area for ``level``.

    If ``lat`` is provided, area is computed for a cell centered at that latitude.
    If omitted, returns the equatorial upper bound.
    """

    depth = _validate_level(level)
    side_deg = level_degrees(depth)
    center_lat = 0.0 if lat is None else max(-90.0, min(90.0, float(lat)))
    half = side_deg / 2.0
    lat1 = max(-90.0, center_lat - half)
    lat2 = min(90.0, center_lat + half)

    dlon = math.radians(side_deg)
    area_km2 = (_EARTH_RADIUS_KM ** 2) * dlon * abs(math.sin(math.radians(lat2)) - math.sin(math.radians(lat1)))
    return area_km2 * _area_unit_scale(unit)


def _polygon_area_km2(ring: Sequence[tuple[float, float]]) -> float:
    closed = _close_ring(ring)
    lats = [p[1] for p in closed[:-1]]
    lat0 = sum(lats) / max(1, len(lats))
    cos_lat = max(math.cos(math.radians(lat0)), 1e-8)

    coords: list[tuple[float, float]] = []
    for lon, lat in closed:
        x = math.radians(lon) * _EARTH_RADIUS_KM * cos_lat
        y = math.radians(lat) * _EARTH_RADIUS_KM
        coords.append((x, y))

    area = 0.0
    for i in range(len(coords) - 1):
        x1, y1 = coords[i]
        x2, y2 = coords[i + 1]
        area += (x1 * y2) - (x2 * y1)
    return abs(area) / 2.0


def _bbox_cell_count(min_lon: float, min_lat: float, max_lon: float, max_lat: float, level: int) -> int:
    depth = _validate_level(level)
    min_lon, min_lat, max_lon, max_lat = _normalize_bbox(min_lon, min_lat, max_lon, max_lat)
    step = level_degrees(depth)

    lat_cells = int(round(180.0 / step))
    lon_cells = int(round(360.0 / step))
    lat_range = _index_range(min_lat, max_lat, -90.0, step, lat_cells)
    if lat_range is None:
        return 0
    lat_count = lat_range[1] - lat_range[0] + 1

    if max_lon - min_lon >= 360.0:
        lon_count = lon_cells
    else:
        min_w = _wrap_lon(min_lon)
        max_w = _wrap_lon(max_lon)
        if min_w <= max_w:
            r = _index_range(min_w, max_w, -180.0, step, lon_cells)
            lon_count = 0 if r is None else (r[1] - r[0] + 1)
        else:
            r1 = _index_range(min_w, 180.0, -180.0, step, lon_cells)
            r2 = _index_range(-180.0, max_w, -180.0, step, lon_cells)
            c1 = 0 if r1 is None else (r1[1] - r1[0] + 1)
            c2 = 0 if r2 is None else (r2[1] - r2[0] + 1)
            lon_count = c1 + c2

    return lat_count * lon_count


def estimate_cell_count(
    exterior: list[tuple[float, float]] | None,
    level: int,
    *,
    bbox: tuple[float, float, float, float] | None = None,
) -> int:
    """Estimate polygon/bbox fill count at ``level`` without materializing cells."""

    depth = _validate_level(level)
    if bbox is not None:
        if len(bbox) != 4:
            raise ValueError("bbox must be (min_lon, min_lat, max_lon, max_lat)")
        return _bbox_cell_count(bbox[0], bbox[1], bbox[2], bbox[3], depth)

    if exterior is None:
        raise ValueError("exterior or bbox must be provided")

    ext = _unwrap_ring(_close_ring(exterior))
    min_lon, min_lat, max_lon, max_lat = _ring_bounds(ext)
    bbox_count = _bbox_cell_count(min_lon, min_lat, max_lon, max_lat, depth)
    if bbox_count == 0:
        return 0

    lat_center = (min_lat + max_lat) / 2.0
    poly_area = _polygon_area_km2(ext)
    cell_area = average_cell_area(depth, lat=lat_center, unit="km^2")
    if cell_area <= 0:
        return 0

    estimate = int(round(poly_area / cell_area))
    return max(1, min(bbox_count, estimate))


# h3-like convenience aliases
def latlng_to_cell(lat: float, lng: float, res: int) -> str:
    """h3-like alias using ``(lat, lng, res)`` argument order."""

    return encode(lng, lat, res)


def cell_to_latlng(cell: str) -> tuple[float, float]:
    """h3-like alias returning ``(lat, lng)`` centroid."""

    lon, lat = decode_centroid(cell)
    return (lat, lon)


def average_hexagon_area(res: int, unit: str = "km^2") -> float:
    """h3-like alias for average area at the equator in requested units."""

    return average_cell_area(res, unit=unit)
