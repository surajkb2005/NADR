from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel


class RiskLevel(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class SimulationScenario(str, Enum):
    NORMAL = "normal"
    MODERATE = "moderate"
    SEVERE = "severe"


class SpaceWeatherData(BaseModel):
    timestamp: datetime
    kp_index: float
    solar_wind_speed: Optional[float] = None
    solar_wind_density: Optional[float] = None
    risk_level: RiskLevel
    estimated_gps_error_m: Tuple[float, float]
    alerts: List[str] = []
    source: str = "NOAA"


class HeatmapRequest(BaseModel):
    bbox: List[float]  # [min_lon, min_lat, max_lon, max_lat]
    resolution: float = 0.02


class RouteRequest(BaseModel):
    start: Tuple[float, float]  # [lat, lon]
    end: Tuple[float, float]  # [lat, lon]
    mode: str = "normal"  # "normal" or "safe"


class RouteResponse(BaseModel):
    route: Optional[Dict[str, Any]] = None
    alternatives: Optional[Dict[str, Any]] = None
    metadata: Optional[Dict[str, Any]] = None


class StormSimulationRequest(BaseModel):
    scenario: SimulationScenario
    latitude: float
    longitude: float


class GPSFailureSimulation(BaseModel):
    risk_level: RiskLevel
    severity: str = "medium"  # "low", "medium", "high"
    start_position: Tuple[float, float]
    duration_seconds: int = 60


class IMUPathRequest(BaseModel):
    start: Tuple[float, float]
    end: Tuple[float, float]
    avoid_high_risk: bool = True


class HealthResponse(BaseModel):
    status: str
    timestamp: datetime
    services: Dict[str, bool]
