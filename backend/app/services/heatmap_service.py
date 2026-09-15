import logging
from typing import Any, Dict, List, Tuple

import geojson
import numpy as np

from ..models import HeatmapRequest, RiskLevel
from .risk_service import RiskAssessmentService

logger = logging.getLogger(__name__)


class HeatmapGenerator:
    def __init__(self):
        self.risk_service = RiskAssessmentService()

    def generate_heatmap(
        self, request: HeatmapRequest, kp_index: float
    ) -> Dict[str, Any]:
        """Generate GeoJSON heatmap"""
        min_lon, min_lat, max_lon, max_lat = request.bbox
        resolution = request.resolution

        lats = np.arange(min_lat, max_lat, resolution)
        lons = np.arange(min_lon, max_lon, resolution)

        features = []

        for i in range(len(lats) - 1):
            for j in range(len(lons) - 1):
                cell_min_lat = lats[i]
                cell_max_lat = lats[i + 1]
                cell_min_lon = lons[j]
                cell_max_lon = lons[j + 1]

                center_lat = (cell_min_lat + cell_max_lat) / 2
                center_lon = (cell_min_lon + cell_max_lon) / 2

                risk_score = self.risk_service.calculate_grid_risk_score(
                    kp_index, center_lat, center_lon
                )

                if risk_score < 40:
                    risk_level = RiskLevel.LOW
                    color = "#4CAF50"
                elif risk_score < 70:
                    risk_level = RiskLevel.MEDIUM
                    color = "#FFC107"
                else:
                    risk_level = RiskLevel.HIGH
                    color = "#F44336"

                polygon = geojson.Polygon(
                    [
                        [
                            [cell_min_lon, cell_min_lat],
                            [cell_min_lon, cell_max_lat],
                            [cell_max_lon, cell_max_lat],
                            [cell_max_lon, cell_min_lat],
                            [cell_min_lon, cell_min_lat],
                        ]
                    ]
                )

                feature = geojson.Feature(
                    geometry=polygon,
                    properties={
                        "risk_level": risk_level.value,
                        "risk_score": round(risk_score, 1),
                        "color": color,
                        "opacity": min(0.7, risk_score / 150),
                        "center": [center_lon, center_lat],
                        "gps_error_min": self.risk_service.estimate_gps_error(
                            risk_level, center_lat
                        )[0],
                        "gps_error_max": self.risk_service.estimate_gps_error(
                            risk_level, center_lat
                        )[1],
                    },
                )
                features.append(feature)

        return {
            "type": "FeatureCollection",
            "features": features,
            "metadata": {
                "bbox": request.bbox,
                "resolution": resolution,
                "grid_size": f"{len(lats)-1}x{len(lons)-1}",
                "kp_index": kp_index,
            },
        }
