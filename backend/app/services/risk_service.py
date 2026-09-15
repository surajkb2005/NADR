import logging
import math
import random
from typing import List, Tuple

from ..models import RiskLevel, SimulationScenario, SpaceWeatherData

logger = logging.getLogger(__name__)


class RiskAssessmentService:
    def __init__(self):
        self.risk_thresholds = {
            RiskLevel.LOW: (0, 3.99),
            RiskLevel.MEDIUM: (4, 6.99),
            RiskLevel.HIGH: (7, 9),
        }

        self.base_gps_errors = {
            RiskLevel.LOW: (5, 15),
            RiskLevel.MEDIUM: (30, 100),
            RiskLevel.HIGH: (100, 500),
        }

        # Region-specific risk multipliers (simulating geomagnetic variations)
        self.risk_regions = {
            "north_america": {
                "lat_range": (20, 70),
                "lon_range": (-130, -60),
                "multiplier": 1.0,
            },
            "europe": {
                "lat_range": (35, 70),
                "lon_range": (-10, 40),
                "multiplier": 1.2,
            },
            "asia": {"lat_range": (10, 60), "lon_range": (60, 150), "multiplier": 1.1},
            "south_pole": {
                "lat_range": (-90, -60),
                "lon_range": (-180, 180),
                "multiplier": 2.0,
            },
            "north_pole": {
                "lat_range": (60, 90),
                "lon_range": (-180, 180),
                "multiplier": 1.8,
            },
        }

    def calculate_risk_level(
        self, kp_index: float, solar_wind_speed: float = None, latitude: float = None
    ) -> RiskLevel:
        """Calculate risk level based on Kp index and location"""
        if kp_index < 4:
            base_risk = RiskLevel.LOW
        elif kp_index < 7:
            base_risk = RiskLevel.MEDIUM
        else:
            base_risk = RiskLevel.HIGH

        # Solar wind adjustment
        if solar_wind_speed and solar_wind_speed > 600:
            if base_risk == RiskLevel.LOW:
                base_risk = RiskLevel.MEDIUM
            elif base_risk == RiskLevel.MEDIUM:
                base_risk = RiskLevel.HIGH

        # Latitude adjustment (higher latitudes = higher risk)
        if latitude is not None:
            abs_lat = abs(latitude)
            if abs_lat > 60 and base_risk != RiskLevel.HIGH:
                base_risk = (
                    RiskLevel.MEDIUM if base_risk == RiskLevel.LOW else RiskLevel.HIGH
                )

        return base_risk

    def estimate_gps_error(
        self, risk_level: RiskLevel, latitude: float = None, scenario: str = "normal"
    ) -> Tuple[float, float]:
        """Estimate GPS error range with scenario adjustments"""
        min_error, max_error = self.base_gps_errors[risk_level]

        # Scenario adjustments
        scenario_multiplier = {"normal": 1.0, "moderate": 1.5, "severe": 2.5}.get(
            scenario, 1.0
        )

        min_error *= scenario_multiplier
        max_error *= scenario_multiplier

        # Latitude adjustment
        if latitude is not None:
            abs_lat = abs(latitude)
            if abs_lat > 60:
                min_error *= 1.8
                max_error *= 1.8
            elif abs_lat > 45:
                min_error *= 1.3
                max_error *= 1.3

        # Add randomness
        random_factor = 0.8 + random.random() * 0.4
        actual_min = min_error * random_factor
        actual_max = max_error * random_factor

        return (round(actual_min, 1), round(actual_max, 1))

    def calculate_grid_risk_score(
        self,
        kp_index: float,
        latitude: float,
        longitude: float,
        scenario: str = "normal",
    ) -> float:
        """Calculate risk score (0-100) for a grid cell"""
        base_score = (kp_index / 9) * 70

        # Geomagnetic effect based on latitude
        geomag_factor = self._calculate_geomagnetic_factor(latitude)

        # Regional adjustments
        region_factor = self._get_region_factor(latitude, longitude)

        # Scenario multiplier
        scenario_factor = {"normal": 1.0, "moderate": 1.5, "severe": 2.0}.get(
            scenario, 1.0
        )

        total_score = base_score * geomag_factor * region_factor * scenario_factor

        # Add some local variation
        local_variation = 0.8 + random.random() * 0.4
        total_score *= local_variation

        return min(100, total_score)

    def _calculate_geomagnetic_factor(self, latitude: float) -> float:
        """Calculate geomagnetic effect factor"""
        abs_lat = abs(latitude)
        if abs_lat > 70:
            return 2.0
        elif abs_lat > 50:
            return 1.5
        elif abs_lat > 30:
            return 1.2
        else:
            return 1.0

    def _get_region_factor(self, latitude: float, longitude: float) -> float:
        """Get risk multiplier for specific region"""
        for region, config in self.risk_regions.items():
            min_lat, max_lat = config["lat_range"]
            min_lon, max_lon = config["lon_range"]

            if min_lat <= latitude <= max_lat and min_lon <= longitude <= max_lon:
                return config["multiplier"]

        return 1.0

    def process_space_weather_data(
        self, data: SpaceWeatherData, latitude: float = None, scenario: str = "normal"
    ) -> SpaceWeatherData:
        """Process space weather data to calculate risks"""
        risk_level = self.calculate_risk_level(
            data.kp_index, data.solar_wind_speed, latitude
        )

        error_range = self.estimate_gps_error(risk_level, latitude, scenario)

        data.risk_level = risk_level
        data.estimated_gps_error_m = error_range

        # Add alerts based on conditions
        if risk_level == RiskLevel.HIGH:
            data.alerts.append(
                "⚠️ SEVERE: Geomagnetic storm - GPS degradation expected"
            )
            data.alerts.append(
                "Recommend: Use storm-safe routing and prepare for IMU navigation"
            )
        elif risk_level == RiskLevel.MEDIUM:
            data.alerts.append(
                "⚠️ MODERATE: Elevated space weather - Monitor GPS accuracy"
            )
            if data.solar_wind_speed and data.solar_wind_speed > 600:
                data.alerts.append(
                    "High solar wind detected - Increased GPS error possible"
                )
        elif risk_level == RiskLevel.LOW and scenario == "severe":
            data.alerts.append(
                "ℹ️ Simulated severe storm - GPS errors artificially increased"
            )

        return data

    def get_drift_severity(self, kp_index: float) -> str:
        """Get drift severity level based on Kp index"""
        if kp_index < 4:
            return "low"
        elif kp_index < 7:
            return "medium"
        else:
            return "high"
