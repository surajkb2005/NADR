import logging
import math
import random
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

# import requests
import httpx

from ..models import RiskLevel, RouteRequest
from ..utils.geo_utils import haversine_distance
from .risk_service import RiskAssessmentService

logger = logging.getLogger(__name__)


class RoadNetworkRouter:
    def __init__(self):
        self.risk_service = RiskAssessmentService()
        self.osrm_base_url = "http://router.project-osrm.org/route/v1/driving"

    # def get_osrm_route(
    #     self, start: Tuple[float, float], end: Tuple[float, float]
    # ) -> Optional[List[List[float]]]:
    #     """Fetch real road geometry from OSRM public API"""
    #     try:
    #         # OSRM expects {lon},{lat}
    #         url = f"{self.osrm_base_url}/{start[1]},{start[0]};{end[1]},{end[0]}"
    #         params = {"overview": "full", "geometries": "geojson"}

    #         response = requests.get(url, params=params, timeout=5.0)
    #         if response.status_code == 200:
    #             data = response.json()
    #             if data["code"] == "Ok" and len(data["routes"]) > 0:
    #                 # OSRM returns [lon, lat], we need [lat, lon]
    #                 coordinates = data["routes"][0]["geometry"]["coordinates"]
    #                 return [[lat, lon] for lon, lat in coordinates]
    #         return None
    #     except Exception as e:
    #         logger.error(f"OSRM Fetch Error: {e}")
    #         return None

    async def get_osrm_route(
        self, start: Tuple[float, float], end: Tuple[float, float]
    ) -> Optional[List[List[float]]]:
        """Fetch real road geometry from OSRM public API (async)"""
        try:
            url = f"{self.osrm_base_url}/{start[1]},{start[0]};{end[1]},{end[0]}"
            params = {"overview": "full", "geometries": "geojson"}

            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(url, params=params)
                if response.status_code == 200:
                    data = response.json()
                    if data["code"] == "Ok" and len(data["routes"]) > 0:
                        coordinates = data["routes"][0]["geometry"]["coordinates"]
                        return [[lat, lon] for lon, lat in coordinates]
            return None
        except httpx.TimeoutException:
            logger.error("OSRM request timed out")
            return None
        except Exception as e:
            logger.error(f"OSRM Fetch Error: {e}")
            return None

    def calculate_route_metrics(
        self, path: List[List[float]], kp_index: float, scenario: str
    ) -> Dict[str, Any]:
        """Calculate distance, time, and risk along a specific path"""
        if not path or len(path) < 2:
            return {}

        total_distance = 0
        total_risk = 0
        max_risk = 0
        risk_segments = {"low": 0, "medium": 0, "high": 0}

        for i in range(len(path)):
            lat, lon = path[i]

            # Risk at this specific point
            risk = (
                self.risk_service.calculate_grid_risk_score(
                    kp_index, lat, lon, scenario
                )
                / 100.0
            )

            total_risk += risk
            max_risk = max(max_risk, risk)

            if risk > 0.7:
                risk_segments["high"] += 1
            elif risk > 0.4:
                risk_segments["medium"] += 1
            else:
                risk_segments["low"] += 1

            if i > 0:
                prev = path[i - 1]
                total_distance += haversine_distance(prev[0], prev[1], lat, lon)

        avg_risk = total_risk / len(path) if len(path) > 0 else 0

        if max_risk > 0.7:
            max_risk_zone = RiskLevel.HIGH
        elif max_risk > 0.4:
            max_risk_zone = RiskLevel.MEDIUM
        else:
            max_risk_zone = RiskLevel.LOW

        return {
            "path": path,
            "distance_m": round(total_distance, 1),
            "estimated_time_s": round(total_distance / 15.0, 1),
            "total_risk_score": round(avg_risk * 100, 1),
            "max_risk_zone": max_risk_zone,
            "avg_risk": round(avg_risk, 3),
            "risk_segments": risk_segments,
        }

    def _generate_drifted_path(
        self, path: List[List[float]], kp_index: float
    ) -> List[List[float]]:
        """
        Generate a 'drifted' version of the path to simulate GPS error.
        Only generates significant drift if Kp is high (Real NOAA Data or Simulation).
        """
        if not path:
            return []

        # Seed random with path geometry so drift is consistent for the same route
        seed_val = int(len(path) * 1000 + path[0][0] * 100 + kp_index * 10)
        random.seed(seed_val)

        drifted_path = []

        # --- DRIFT SCALING BASED ON Kp ---
        if kp_index < 4:
            # NORMAL MODE (REALITY): GPS is accurate.
            # Almost zero drift (2-5 meters is standard GPS margin of error)
            # This effectively "removes the guessing" for normal conditions.
            bias_scale = 2
            noise_scale = 3
        elif kp_index < 7:
            # MODERATE STORM: Significant drift (500m)
            bias_scale = 500
            noise_scale = 100
        else:
            # SEVERE STORM: Extreme drift (2.5 km)
            bias_scale = 2500
            noise_scale = 400

        # Random initial direction for the "Systematic Bias"
        angle = random.uniform(0, 2 * math.pi)

        # Pre-calculate base bias in degrees
        base_lat_bias = (bias_scale * math.sin(angle)) / 111000
        base_lon_bias = (bias_scale * math.cos(angle)) / 111000

        # Apply drift to each point
        for i, (lat, lon) in enumerate(path):
            # 1. Random Noise (Jitter) per point
            lat_noise = (random.uniform(-1, 1) * noise_scale) / 111000
            lon_noise = (random.uniform(-1, 1) * noise_scale) / 111000

            # 2. "Wandering" Bias
            # Only apply significant wander if we are actually drifting
            if kp_index >= 4:
                wander_factor = math.sin(i / 5.0) * 0.8
            else:
                wander_factor = 0  # Stable path for normal mode

            current_lat_bias = base_lat_bias * (1 + wander_factor)
            current_lon_bias = base_lon_bias * (1 + wander_factor)

            new_lat = lat + current_lat_bias + lat_noise
            new_lon = lon + current_lon_bias + lon_noise

            drifted_path.append([new_lat, new_lon])

        return drifted_path

    async def find_routes(
        self, request: RouteRequest, kp_index: float = 2.0, scenario: str = "normal"
    ) -> Dict[str, Any]:
        """Get Real Road Route, analyze risk, and generate simulations"""

        road_path = await self.get_osrm_route(request.start, request.end)
        routes = {}

        if road_path:
            # NORMAL ROUTE
            normal_metrics = self.calculate_route_metrics(road_path, kp_index, scenario)
            routes["normal"] = {
                **normal_metrics,
                "optimization": "fastest_road",
                "risk_weight": 0.0,
            }

            # DRIFTED ROUTE (Simulated GPS Error)
            # Will be nearly identical to Normal if Kp < 4 (Real Data)
            # Will be wildly different if Kp >= 4 (Simulated or Real Storm)
            drifted_coords = self._generate_drifted_path(road_path, kp_index)
            drifted_metrics = self.calculate_route_metrics(
                drifted_coords, kp_index, scenario
            )

            routes["drifted"] = {
                **drifted_metrics,
                "optimization": "gps_error_simulation",
                "risk_weight": 0.0,
                "description": "Simulated GPS path based on current Kp index",
            }

            # SAFE ROUTE
            routes["safe"] = {
                **normal_metrics,
                "optimization": "safe_road",
                "risk_weight": 1.0,
            }

            routes["imu"] = routes["normal"].copy()

        else:
            # Fallback
            logger.warning("OSRM failed, using straight line fallback")
            start, end = request.start, request.end
            fallback_path = [list(start), list(end)]
            fallback_metrics = self.calculate_route_metrics(
                fallback_path, kp_index, scenario
            )

            routes["normal"] = {**fallback_metrics, "optimization": "fallback"}
            routes["safe"] = {**fallback_metrics, "optimization": "fallback"}
            routes["drifted"] = {**fallback_metrics, "optimization": "fallback"}
            routes["imu"] = {**fallback_metrics, "optimization": "fallback"}

        return {
            "alternatives": routes,
            "metadata": {
                "start": request.start,
                "end": request.end,
                "source": "OSRM Public API",
                "kp_index": kp_index,
            },
        }
