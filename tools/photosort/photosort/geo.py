"""Home-cluster detection and distance-from-home (for the Travel category)."""

from __future__ import annotations

import math
from collections import Counter
from statistics import median


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371.0088 * math.asin(min(1.0, math.sqrt(a)))


def valid_point(lat, lon) -> bool:
    return (
        lat is not None and lon is not None
        and -90 <= lat <= 90 and -180 <= lon <= 180
        and not (abs(lat) < 1e-9 and abs(lon) < 1e-9)
    )


def find_home(points: list[tuple[float, float]], min_points: int = 25, cell_deg: float = 0.1,
              radius_km: float = 30.0) -> tuple[float, float] | None:
    """Densest ~11 km grid cell, refined to the median of everything within radius_km of it."""
    pts = [(a, b) for a, b in points if valid_point(a, b)]
    if len(pts) < min_points:
        return None
    cells = Counter((round(a / cell_deg), round(b / cell_deg)) for a, b in pts)
    (ci, cj), _ = cells.most_common(1)[0]
    c_lat, c_lon = ci * cell_deg, cj * cell_deg
    near = [(a, b) for a, b in pts if haversine_km(a, b, c_lat, c_lon) <= radius_km]
    if not near:
        return c_lat, c_lon
    return median(a for a, _ in near), median(b for _, b in near)


def resolve_home(travel_cfg: dict, points: list[tuple[float, float]]) -> tuple[float, float] | None:
    home = travel_cfg.get("home", "auto")
    if home != "auto":
        return float(home[0]), float(home[1])
    return find_home(points, int(travel_cfg.get("min_gps_photos", 25)))
