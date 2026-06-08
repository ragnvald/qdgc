"""Core encoding and decoding helpers for Extended QDGC."""

from __future__ import annotations

from dataclasses import dataclass
import math
import re
from typing import Iterable, Sequence


_CODE_RE = re.compile(r"^(?P<lon_hem>[EW])(?P<lon_deg>\d{3})(?P<lat_hem>[NS])(?P<lat_deg>\d{2})(?P<path>[ABCD]*)$")


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
