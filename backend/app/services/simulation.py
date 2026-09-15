import math
import random
from datetime import datetime, timedelta
from typing import Any, Dict, List, Tuple

from ..models import (
    GPSFailureSimulation,
    RiskLevel,
    SimulationScenario,
    SpaceWeatherData,
)
from .risk_service import RiskAssessmentService


class StormSimulator:
    def __init__(self):
        self.risk_service = RiskAssessmentService()
        self.scenarios = {
            SimulationScenario.NORMAL: {
                "kp_base": 2.0,
                "kp_variation": 0.5,
                "solar_wind": 400,
                "description": "Normal space weather conditions",
            },
            SimulationScenario.MODERATE: {
                "kp_base": 5.0,
                "kp_variation": 1.0,
                "solar_wind": 550,
                "description": "Moderate geomagnetic storm",
            },
            SimulationScenario.SEVERE: {
                "kp_base": 8.0,
                "kp_variation": 0.7,
                "solar_wind": 700,
                "description": "Severe geomagnetic storm",
            },
        }

    def generate_storm_timeline(
        self, scenario: SimulationScenario
    ) -> List[Dict[str, Any]]:
        """Generate detailed storm timeline"""
        config = self.scenarios[scenario]
        timeline = []

        now = datetime.utcnow()

        # Generate 24 data points (2 hours of simulation)
        for i in range(24):
            time = now - timedelta(minutes=5 * i)
            progress = i / 24

            if i < 6:
                phase = "quiet"
                kp = config["kp_base"] * 0.3 + random.uniform(-0.2, 0.2)
                phase_desc = "Pre-storm quiet period"
            elif i < 12:
                phase = "onset"
                kp = config["kp_base"] * (0.3 + 0.7 * (i - 6) / 6) + random.uniform(
                    -0.3, 0.3
                )
                phase_desc = "Storm onset - conditions deteriorating"
            elif i < 18:
                phase = "peak"
                kp = config["kp_base"] + random.uniform(
                    -config["kp_variation"], config["kp_variation"]
                )
                phase_desc = "Storm peak - maximum impact"
            else:
                phase = "recovery"
                kp = config["kp_base"] * (1 - 0.8 * (i - 18) / 6) + random.uniform(
                    -0.2, 0.2
                )
                phase_desc = "Storm recovery - conditions improving"

            risk_level = self.risk_service.calculate_risk_level(kp)

            timeline.append(
                {
                    "timestamp": time.isoformat() + "Z",
                    "kp_index": round(kp, 1),
                    "phase": phase,
                    "phase_description": phase_desc,
                    "risk_level": risk_level.value,
                    "gps_error_min": self.risk_service.base_gps_errors[risk_level][0],
                    "gps_error_max": self.risk_service.base_gps_errors[risk_level][1],
                }
            )

        return timeline

    def get_simulated_weather(
        self, scenario: SimulationScenario, latitude: float, longitude: float
    ) -> SpaceWeatherData:
        """Get simulated space weather for specific location"""
        config = self.scenarios[scenario]

        kp = config["kp_base"] + random.uniform(
            -config["kp_variation"] / 2, config["kp_variation"] / 2
        )
        solar_wind = config["solar_wind"] + random.uniform(-50, 50)

        # Process with risk service
        weather_data = SpaceWeatherData(
            timestamp=datetime.utcnow(),
            kp_index=round(kp, 1),
            solar_wind_speed=round(solar_wind, 1),
            solar_wind_density=random.uniform(5, 10),
            risk_level=RiskLevel.LOW,  # Will be calculated
            estimated_gps_error_m=(5, 15),
            alerts=[f"Simulated {scenario.value} storm: {config['description']}"],
            source=scenario.value.upper(),
        )

        # Process with scenario-specific adjustments
        processed_data = self.risk_service.process_space_weather_data(
            weather_data, latitude, scenario.value
        )

        return processed_data

    def simulate_gps_failure(self, simulation: GPSFailureSimulation) -> Dict[str, Any]:
        """Simulate GPS failure and drift pattern"""
        risk_level = simulation.risk_level
        severity = simulation.severity
        start_lat, start_lon = simulation.start_position

        # Calculate drift parameters based on risk and severity
        drift_params = self._calculate_drift_parameters(risk_level, severity)

        # Generate drift path
        drift_path = []
        current_lat, current_lon = start_lat, start_lon
        drift_path.append([current_lat, current_lon])

        # Simulate drift over time
        for step in range(simulation.duration_seconds // 5):  # 5-second intervals
            # Apply drift
            drift_lat, drift_lon = self._apply_drift_step(
                current_lat, current_lon, drift_params, step
            )

            current_lat, current_lon = drift_lat, drift_lon
            drift_path.append([current_lat, current_lon])

        # Calculate statistics
        total_drift_distance = self._calculate_total_drift(drift_path)

        return {
            "drift_path": drift_path,
            "total_drift_m": round(total_drift_distance, 1),
            "drift_rate_mps": round(
                total_drift_distance / simulation.duration_seconds, 2
            ),
            "severity": severity,
            "risk_level": risk_level.value,
            "duration_s": simulation.duration_seconds,
            "start_position": simulation.start_position,
            "end_position": [current_lat, current_lon],
        }

    def _calculate_drift_parameters(
        self, risk_level: RiskLevel, severity: str
    ) -> Dict[str, float]:
        """Calculate drift parameters based on conditions"""
        # Base drift magnitude (degrees per step)
        base_drift = {
            "low": 0.00002,  # ~2.2m per step
            "medium": 0.0001,  # ~11m per step
            "high": 0.0003,  # ~33m per step
        }.get(severity, 0.0001)

        # Risk level multiplier
        risk_multiplier = {
            RiskLevel.LOW: 0.5,
            RiskLevel.MEDIUM: 1.0,
            RiskLevel.HIGH: 2.0,
        }.get(risk_level, 1.0)

        return {
            "magnitude": base_drift * risk_multiplier,
            "direction_change": random.uniform(0, math.pi),  # Initial direction
            "randomness": 0.3,  # Random component strength
            "systematic_bias": random.uniform(-0.1, 0.1),  # Systematic drift bias
        }

    def _apply_drift_step(
        self, lat: float, lon: float, params: Dict[str, float], step: int
    ) -> Tuple[float, float]:
        """Apply one step of drift simulation"""
        # Update direction with randomness and systematic bias
        params["direction_change"] += (random.random() - 0.5) * params["randomness"]
        params["direction_change"] += params["systematic_bias"]

        # Add some periodic variation
        periodic_variation = 0.1 * math.sin(step / 10.0)
        params["direction_change"] += periodic_variation

        # Calculate drift components
        drift_lat = params["magnitude"] * math.sin(params["direction_change"])
        drift_lon = params["magnitude"] * math.cos(params["direction_change"])

        # Apply drift
        new_lat = lat + drift_lat
        new_lon = lon + drift_lon

        return new_lat, new_lon

    def _calculate_total_drift(self, drift_path: List[List[float]]) -> float:
        """Calculate total drift distance in meters"""
        if len(drift_path) < 2:
            return 0

        total_distance = 0
        for i in range(1, len(drift_path)):
            lat1, lon1 = drift_path[i - 1]
            lat2, lon2 = drift_path[i]

            # Approximate distance (simplified for performance)
            lat_diff = (lat2 - lat1) * 111000  # meters per degree latitude
            lon_diff = (lon2 - lon1) * 111000 * math.cos(lat1 * math.PI / 180)

            segment_distance = math.sqrt(lat_diff**2 + lon_diff**2)
            total_distance += segment_distance

        return total_distance
