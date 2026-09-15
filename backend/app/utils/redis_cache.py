"""
Redis-based async cache utility.
Replaces the old MemoryCache, using the same Redis connection as the rest of the app.
"""

import logging
from typing import Any, Optional
import json

from redis.asyncio import Redis

logger = logging.getLogger(__name__)


class RedisCache:
    def __init__(self, redis: Redis):
        self.redis = redis

    async def get(self, key: str) -> Optional[Any]:
        try:
            value = await self.redis.get(key)
            if value:
                # We serialise values with JSON; deserialise on get.
                return json.loads(value)
            return None
        except Exception as e:
            logger.error(f"Redis cache get error for key '{key}': {e}")
            return None

    async def set(self, key: str, value: Any, ttl: int = 300):
        try:
            await self.redis.setex(key, ttl, json.dumps(value, default=str))
        except Exception as e:
            logger.error(f"Redis cache set error for key '{key}': {e}")

    async def delete(self, key: str):
        """Delete a single key (exact match only; wildcards not yet required)."""
        try:
            await self.redis.delete(key)
        except Exception as e:
            logger.error(f"Redis cache delete error for key '{key}': {e}")

    async def clear(self):
        """Flush the *entire* Redis database – use with extreme caution."""
        logger.warning("FLUSHDB called on Redis cache – all keys removed.")
        await self.redis.flushdb()

    async def ping(self) -> bool:
        try:
            result = await self.redis.ping()
            return result
        except Exception:
            return False
