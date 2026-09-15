import asyncio
import logging
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


class MemoryCache:
    """Simple in-memory cache with wildcard support"""

    def __init__(self):
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()

    async def get(self, key: str) -> Optional[Any]:
        async with self._lock:
            if key in self._cache:
                entry = self._cache[key]
                if entry["expires_at"] > datetime.utcnow():
                    return entry["value"]
                else:
                    del self._cache[key]
            return None

    async def set(self, key: str, value: Any, ttl: int = 300):
        async with self._lock:
            self._cache[key] = {
                "value": value,
                "expires_at": datetime.utcnow() + timedelta(seconds=ttl),
                "created_at": datetime.utcnow(),
            }

    async def delete(self, key: str):
        """Delete a key. Supports wildcards (e.g., 'prefix_*')"""
        async with self._lock:
            # Handle wildcard deletion
            if key.endswith("*"):
                prefix = key[:-1]
                # Find all keys matching the prefix
                keys_to_remove = [k for k in self._cache if k.startswith(prefix)]
                count = 0
                for k in keys_to_remove:
                    del self._cache[k]
                    count += 1
                logger.info(
                    f"Cache wildcard delete: Removed {count} keys for pattern '{key}'"
                )
            # Handle exact key deletion
            elif key in self._cache:
                del self._cache[key]

    async def clear(self):
        async with self._lock:
            self._cache.clear()

    async def ping(self) -> bool:
        return True


# Global cache instance
cache = MemoryCache()
