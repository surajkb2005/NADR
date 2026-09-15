import math
from typing import List, Tuple


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two points in meters"""
    R = 6371000  # Earth radius in meters

    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2) ** 2
    )
    c = 2 * math.asin(math.sqrt(a))

    return R * c


def calculate_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate initial bearing between two points in degrees (0-360)"""
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlon_rad = math.radians(lon2 - lon1)

    y = math.sin(dlon_rad) * math.cos(lat2_rad)
    x = math.cos(lat1_rad) * math.sin(lat2_rad) - math.sin(lat1_rad) * math.cos(
        lat2_rad
    ) * math.cos(dlon_rad)

    bearing = math.degrees(math.atan2(y, x))
    return (bearing + 360) % 360


def calculate_intermediate_point(
    lat1: float, lon1: float, lat2: float, lon2: float, fraction: float
) -> Tuple[float, float]:
    """Calculate intermediate point along great circle path"""
    if fraction <= 0:
        return (lat1, lon1)
    if fraction >= 1:
        return (lat2, lon2)

    # Convert to radians
    lat1_rad = math.radians(lat1)
    lon1_rad = math.radians(lon1)
    lat2_rad = math.radians(lat2)
    lon2_rad = math.radians(lon2)

    # Angular distance
    delta = 2 * math.asin(
        math.sqrt(
            math.sin((lat2_rad - lat1_rad) / 2) ** 2
            + math.cos(lat1_rad)
            * math.cos(lat2_rad)
            * math.sin((lon2_rad - lon1_rad) / 2) ** 2
        )
    )

    if delta == 0:
        return (lat1, lon1)

    a = math.sin((1 - fraction) * delta) / math.sin(delta)
    b = math.sin(fraction * delta) / math.sin(delta)

    x = a * math.cos(lat1_rad) * math.cos(lon1_rad) + b * math.cos(lat2_rad) * math.cos(
        lon2_rad
    )
    y = a * math.cos(lat1_rad) * math.sin(lon1_rad) + b * math.cos(lat2_rad) * math.sin(
        lon2_rad
    )
    z = a * math.sin(lat1_rad) + b * math.sin(lat2_rad)

    lat3_rad = math.atan2(z, math.sqrt(x**2 + y**2))
    lon3_rad = math.atan2(y, x)

    return (math.degrees(lat3_rad), math.degrees(lon3_rad))


def calculate_path_points(
    start: Tuple[float, float], end: Tuple[float, float], num_points: int = 10
) -> List[Tuple[float, float]]:
    """Calculate multiple points along path between start and end"""
    points = []
    for i in range(num_points + 1):
        fraction = i / num_points
        point = calculate_intermediate_point(
            start[0], start[1], end[0], end[1], fraction
        )
        points.append(point)
    return points


def calculate_drift_offset(
    lat: float, lon: float, distance_m: float, bearing_deg: float
) -> Tuple[float, float]:
    """Calculate new position after drifting given distance and bearing"""
    R = 6371000  # Earth radius in meters

    # Convert to radians
    lat_rad = math.radians(lat)
    lon_rad = math.radians(lon)
    bearing_rad = math.radians(bearing_deg)

    # Angular distance
    angular_distance = distance_m / R

    # Calculate new latitude
    new_lat_rad = math.asin(
        math.sin(lat_rad) * math.cos(angular_distance)
        + math.cos(lat_rad) * math.sin(angular_distance) * math.cos(bearing_rad)
    )

    # Calculate new longitude
    new_lon_rad = lon_rad + math.atan2(
        math.sin(bearing_rad) * math.sin(angular_distance) * math.cos(lat_rad),
        math.cos(angular_distance) - math.sin(lat_rad) * math.sin(new_lat_rad),
    )

    # Normalize longitude to [-180, 180]
    new_lon_rad = (new_lon_rad + 3 * math.pi) % (2 * math.pi) - math.pi

    return (math.degrees(new_lat_rad), math.degrees(new_lon_rad))


def calculate_bounding_box(
    center: Tuple[float, float], radius_km: float = 5
) -> List[float]:
    """Calculate bounding box around center point"""
    lat, lon = center

    # 1 degree latitude ≈ 111.32 km
    lat_delta = radius_km / 111.32
    # 1 degree longitude varies with latitude
    lon_delta = radius_km / (111.32 * math.cos(math.radians(lat)))

    return [
        lon - lon_delta,  # min_lon
        lat - lat_delta,  # min_lat
        lon + lon_delta,  # max_lon
        lat + lat_delta,  # max_lat
    ]
