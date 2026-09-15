import asyncio
import logging
from datetime import datetime, timedelta
from typing import Any, Dict, List

import httpx

from ..cache.memory_cache import cache
from ..models import RiskLevel, SpaceWeatherData

from ..config import settings

logger = logging.getLogger(__name__)


class NOAAWeatherService:
    def __init__(self):
        self.base_url = settings.NOAA_BASE_URL  # ✅ from config
        self.timeout = settings.NOAA_TIMEOUT

    async def fetch_kp_index(self) -> List[Dict[str, Any]]:
        """Fetch Kp index data from NOAA"""
        url = f"{self.base_url}/products/noaa-planetary-k-index.json"
        cache_key = "noaa_kp_data"

        cached = await cache.get(cache_key)
        if cached:
            return cached

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(url)
                response.raise_for_status()
                data = response.json()
                await cache.set(cache_key, data, ttl=300)
                return data
        except Exception as e:
            logger.error(f"Error fetching Kp data: {e}")
            return self._generate_simulated_kp_data()

    async def fetch_solar_wind(self) -> List[Dict[str, Any]]:
        """Fetch solar wind data from NOAA"""
        url = f"{self.base_url}/products/solar-wind/plasma-7-day.json"
        cache_key = "noaa_solar_wind_data"

        cached = await cache.get(cache_key)
        if cached:
            return cached

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(url)
                response.raise_for_status()
                data = response.json()
                await cache.set(cache_key, data, ttl=300)
                return data
        except Exception as e:
            logger.error(f"Error fetching solar wind: {e}")
            return []

    def _generate_simulated_kp_data(self) -> List[List]:
        """Generate simulated Kp data as fallback"""
        now = datetime.utcnow()
        simulated_data = []

        for i in range(24):
            timestamp = (now - timedelta(hours=i)).isoformat() + "Z"
            kp_value = 2.3 + (i % 3) * 0.7
            simulated_data.append([timestamp, kp_value])

        return simulated_data

    async def get_current_space_weather(self) -> SpaceWeatherData:
        try:
            kp_data = await self.fetch_kp_index()
            solar_wind_data = await self.fetch_solar_wind()

            latest_kp = 2.0
            # skip header row (index 0)
            if isinstance(kp_data, list) and len(kp_data) > 1:
                last_entry = kp_data[-1]
                if len(last_entry) > 1:
                    try:
                        latest_kp = float(last_entry[1])
                    except (ValueError, TypeError):
                        latest_kp = 2.0

            solar_wind_speed = 400.0
            if isinstance(solar_wind_data, list) and len(solar_wind_data) > 1:
                last_wind = solar_wind_data[-1]
                if len(last_wind) > 1:
                    try:
                        solar_wind_speed = float(last_wind[1])
                    except (ValueError, TypeError):
                        solar_wind_speed = 400.0

            # CRITICAL: Use named arguments to fix BaseModel error
            return SpaceWeatherData(
                timestamp=datetime.utcnow(),
                kp_index=latest_kp,
                solar_wind_speed=solar_wind_speed,
                risk_level=RiskLevel.LOW,
                estimated_gps_error_m=(5, 15),
                alerts=[],
                source="NOAA",
            )
        except Exception as e:
            logger.error(f"Error getting space weather: {e}")
            return SpaceWeatherData(
                timestamp=datetime.utcnow(),
                kp_index=2.0,
                solar_wind_speed=400.0,
                risk_level=RiskLevel.LOW,
                estimated_gps_error_m=(5, 15),
                alerts=["Data fetch failed"],
                source="FALLBACK",
            )
