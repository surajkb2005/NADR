# check_redis.py
import asyncio
import redis.asyncio as r
from dotenv import load_dotenv
import os

load_dotenv("backend/.env")

async def main():
    redis = r.from_url(os.getenv("REDIS_URL"), decode_responses=True)
    keys = await redis.keys("*")
    print("All keys:", keys)
    startup = await redis.get("api_startup")
    print("api_startup:", startup)
    await redis.close()

asyncio.run(main())