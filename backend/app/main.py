import asyncio
import hashlib
import logging

<<<<<<< HEAD
# import os
=======
import os
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
import random
import smtplib
import time
import json
from datetime import datetime
from email.mime.text import MIMEText
from typing import Any, Dict, List

import redis.asyncio as redis

<<<<<<< HEAD
# from dotenv import load_dotenv
=======
from dotenv import load_dotenv
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
from fastapi import (
    FastAPI,
    HTTPException,
    Request,
    Response,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.middleware.cors import CORSMiddleware
from jose import JWTError, jwt
from pydantic import BaseModel, EmailStr
from starlette.middleware.trustedhost import TrustedHostMiddleware

# import centralized settings
from .config import settings

<<<<<<< HEAD
from .cache.memory_cache import cache
=======
# from .cache.memory_cache import cache
from .utils.redis_cache import RedisCache
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523

# Assuming these modules exist in your project structure
from .models import (
    GPSFailureSimulation,
    HealthResponse,
    HeatmapRequest,
    IMUPathRequest,
    RouteRequest,
    SimulationScenario,
    SpaceWeatherData,
)
from .services.heatmap_service import HeatmapGenerator
from .services.noaa_service import NOAAWeatherService
from .services.risk_service import RiskAssessmentService
from .services.routing_service import RoadNetworkRouter
from .services.simulation import StormSimulator

from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response as FastAPIResponse
import time as time_module

# --- CONFIGURATION ---

# load_dotenv()

<<<<<<< HEAD
# SECRET_KEY = os.getenv("SECRET_KEY", "a-default-secret-key-that-must-be-changed")
# ALGORITHM = "HS256"
# SESSION_EXPIRY_SECONDS = 30 * 60  # 30 minutes

# REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
# redis_client = redis.from_url(REDIS_URL, decode_responses=True)

# SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
# SMTP_PORT = int(os.getenv("SMTP_PORT", 587))
# EMAIL_ADDRESS = os.getenv("EMAIL_ADDRESS")
# EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD")

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
# Now use settings
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = settings.ALGORITHM
SESSION_EXPIRY_SECONDS = settings.SESSION_EXPIRY_SECONDS
REDIS_URL = settings.REDIS_URL

redis_client = redis.from_url(REDIS_URL, decode_responses=True)

<<<<<<< HEAD
# Email config from settings
SMTP_SERVER = settings.SMTP_SERVER
SMTP_PORT = settings.SMTP_PORT
EMAIL_ADDRESS = settings.EMAIL_ADDRESS
EMAIL_PASSWORD = settings.EMAIL_PASSWORD
=======
cache = RedisCache(redis_client)

SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))
EMAIL_ADDRESS = os.getenv("EMAIL_ADDRESS")
EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD")
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523

FRONTEND_URL = os.getenv("FRONTEND_URL")
active_connections: List[WebSocket] = []
imu_connections: Dict[str, WebSocket] = {}
map_connections: Dict[str, List[WebSocket]] = {}

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="StellarRoute API",
    description="Space-weather aware navigation system with GPS failure resilience",
    version="2.0.0",
)

<<<<<<< HEAD
# code before refactor

# origins = [
#     "http://localhost:3000",
#     "http://127.0.0.1:3000",
#     "http://localhost:5173",
#     "http://127.0.0.1:5173",
# ]
# app.add_middleware(
#     CORSMiddleware,
#     allow_origins=origins,
#     allow_credentials=True,
#     allow_methods=["*"],
#     allow_headers=["*"],
# )

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,  # was hardcoded list
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
=======
# Prometheus metrics
REQUEST_COUNT = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
)
ERROR_COUNT = Counter(
    "http_errors_total", "Total HTTP errors (5xx)", ["method", "endpoint"]
)

origins = [FRONTEND_URL]

app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=["stellar-route.me", "localhost", "*.compute.amazonaws.com"],
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start_time = time_module.time()
    response = await call_next(request)
    elapsed = time_module.time() - start_time

    endpoint = request.url.path

    REQUEST_COUNT.labels(
        method=request.method, endpoint=endpoint, status=response.status_code
    ).inc()

    REQUEST_LATENCY.labels(method=request.method, endpoint=endpoint).observe(elapsed)

    if response.status_code >= 500:
        ERROR_COUNT.labels(method=request.method, endpoint=endpoint).inc()

    return response


noaa_service = NOAAWeatherService()
risk_service = RiskAssessmentService()
heatmap_generator = HeatmapGenerator()
router = RoadNetworkRouter()
storm_simulator = StormSimulator()


class EmailRequest(BaseModel):
    email: EmailStr


class OtpVerification(BaseModel):
    email: EmailStr
    otp: str


# --- REDIS STATE HELPERS (USER SCOPED) ---


def get_client_id(request: Request) -> str:
    """Extract user email from JWT, header Client-ID, or fallback to IP."""
    token = request.cookies.get("session_id")
    if token:
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
            if payload.get("sub"):
                return f"user:{payload.get('sub')}"
        except JWTError:
            pass

    # Check for frontend-generated unique Device ID first
    client_id_header = request.headers.get("X-Client-ID")
    if client_id_header:
        return f"guest:{client_id_header}"

    # Fallback to IP address (Only used if someone hits API without frontend)
    client_ip = request.client.host if request.client else "unknown"
    return f"guest:{client_ip}"


async def get_simulation_state(client_id: str) -> dict:
    """Fetch user-specific simulation state from Redis."""
    state_str = await redis_client.get(f"simulation:{client_id}")
    if state_str:
        return json.loads(state_str)
    return {
        "active": False,
        "scenario": None,
        "kp_index": None,
        "latitude": None,
        "longitude": None,
    }


async def set_simulation_state(client_id: str, state: dict):
    """Save user-specific simulation state to Redis with a 2-hour expiration."""
    await redis_client.setex(f"simulation:{client_id}", 7200, json.dumps(state))


async def get_safe_kp_index(client_id: str) -> float:
    """Helper to safely get user-specific Kp index."""
    state = await get_simulation_state(client_id)
    kp = state.get("kp_index")
    if kp is None:
        return 2.0
    return float(kp)


# --- AUTHENTICATION UTILITY FUNCTIONS ---


def generate_otp(length: int = 6) -> str:
    return "".join([str(random.randint(0, 9)) for _ in range(length)])


def send_email_otp(email: EmailStr, otp: str) -> bool:
    if not all([SMTP_SERVER, EMAIL_ADDRESS, EMAIL_PASSWORD]):
        logger.error("Email configuration missing. Cannot send email.")
        return False

    email_body = f"""Dear User,\n\nYour StellarRoute verification code (OTP) is:\n---\n{otp}\n---\n\nThis code is valid for 5 minutes.\n\nThank you,\nThe StellarRoute Team"""
    msg = MIMEText(email_body, "plain", "utf-8")
    msg["Subject"] = "StellarRoute: Your Login Code"
    msg["From"] = EMAIL_ADDRESS
    msg["To"] = email

    try:
        context = smtplib.ssl.create_default_context()
        with smtplib.SMTP_SSL(SMTP_SERVER, 465, context=context) as server:
            server.login(EMAIL_ADDRESS, EMAIL_PASSWORD)
            server.sendmail(EMAIL_ADDRESS, [email], msg.as_string())
        return True
    except Exception as e_ssl:
        logger.warning(f"SSL failed, trying STARTTLS: {e_ssl}")
        try:
            with smtplib.SMTP(SMTP_SERVER, 587) as server:
                server.ehlo()
                server.starttls()
                server.ehlo()
                server.login(EMAIL_ADDRESS, EMAIL_PASSWORD)
                server.sendmail(EMAIL_ADDRESS, [email], msg.as_string())
            return True
        except Exception as e_tls:
            logger.error(f"Failed to send email: {e_tls}")
            return False


def create_session_jwt(email: str) -> str:
    to_encode = {"sub": email, "exp": time.time() + SESSION_EXPIRY_SECONDS}
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


# --- AUTHENTICATION ENDPOINTS ---


@app.post(
    "/auth/request-otp",
    status_code=status.HTTP_202_ACCEPTED,
    tags=["Authentication"],
)
async def request_otp(request: EmailRequest):
    # --- Rate limit: 5 requests per minute per email ---
    rate_key = f"rate:otp:{request.email}"
    current = await redis_client.incr(rate_key)
    if current == 1:
        await redis_client.expire(rate_key, 60)
    if current > 5:
        logger.warning(f"OTP rate limit exceeded for {request.email}")
        raise HTTPException(
            status_code=429,
            detail="Too many OTP requests. Please wait a minute and try again.",
        )
    # --- end rate limit ---

    otp_code = generate_otp()
    if not send_email_otp(request.email, otp_code):
        raise HTTPException(
            status_code=500, detail="Failed to send verification email."
        )
    await redis_client.setex(f"otp:{request.email}", 300, otp_code)
    return {"message": "OTP sent successfully."}


@app.post("/auth/verify-otp", tags=["Authentication"])
async def verify_otp_and_login(request_body: OtpVerification, response: Response):
    stored_otp = await redis_client.get(f"otp:{request_body.email}")
    if not stored_otp or request_body.otp != stored_otp:
        raise HTTPException(status_code=401, detail="Invalid or expired OTP.")

    session_token = create_session_jwt(request_body.email)
    response.set_cookie(
        key="session_id",
        value=session_token,
        httponly=True,
        secure=True,
        max_age=SESSION_EXPIRY_SECONDS,
        samesite="Lax",
    )
    await redis_client.delete(f"otp:{request_body.email}")
    return {"message": "Login successful.", "user_email": request_body.email}


@app.get("/auth/status", tags=["Authentication"])
async def check_auth_status(request: Request):
    token = request.cookies.get("session_id")
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if not payload.get("sub"):
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"status": "authenticated", "user_email": payload.get("sub")}
    except JWTError:
        raise HTTPException(status_code=401, detail="Session expired")


@app.post("/auth/logout", tags=["Authentication"])
async def logout(response: Response):
    response.delete_cookie(key="session_id")
    return {"message": "Logout successful"}


# --- APPLICATION ENDPOINTS ---


@app.get("/")
async def root():
    return {"message": "StellarRoute API v2.0", "status": "operational"}


@app.get("/space-weather/current", response_model=SpaceWeatherData)
async def get_current_space_weather(
    request: Request, latitude: float = 37.7749, longitude: float = -122.4194
):
    client_id = get_client_id(request)
    try:
        sim_state = await get_simulation_state(client_id)
        if sim_state["active"]:
            scenario_enum = SimulationScenario(sim_state["scenario"])
            weather_data = storm_simulator.get_simulated_weather(
                scenario_enum, latitude, longitude
            )
        else:
            weather_data = await noaa_service.get_current_space_weather()

        scenario = "simulation" if sim_state["active"] else "normal"
        return risk_service.process_space_weather_data(weather_data, latitude, scenario)

    except Exception as e:
        logger.error(f"Error getting space weather: {e}")
        return risk_service.process_space_weather_data(
            SpaceWeatherData(
                timestamp=datetime.utcnow(),
                kp_index=2.0,
                risk_level="low",
                estimated_gps_error_m=(5, 15),
                alerts=["Data fetch failed"],
                source="FALLBACK",
            ),
            latitude,
            "normal",
        )


@app.get("/space-weather/simulate")
async def simulate_storm(
    request: Request, scenario: str, latitude: float, longitude: float
):
    client_id = get_client_id(request)
    try:
        scenario_enum = SimulationScenario(scenario)
        weather_data = storm_simulator.get_simulated_weather(
            scenario_enum, latitude, longitude
        )

        new_state = {
            "active": True,
            "scenario": scenario,
            "latitude": latitude,
            "longitude": longitude,
            "kp_index": weather_data.kp_index,
        }
        await set_simulation_state(client_id, new_state)

        return weather_data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/space-weather/stop-simulation")
async def stop_simulation(request: Request):
    client_id = get_client_id(request)
    await set_simulation_state(
        client_id,
        {
            "active": False,
            "scenario": None,
            "kp_index": None,
            "latitude": None,
            "longitude": None,
        },
    )
    return {"message": "Simulation stopped for user", "status": "returned_to_real_data"}


@app.get("/space-weather/timeline")
async def get_storm_timeline(scenario: str = "severe"):
    try:
        scenario_enum = SimulationScenario(scenario)
        return {
            "timeline": storm_simulator.generate_storm_timeline(scenario_enum),
            "scenario": scenario,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/heatmap")
async def get_heatmap(heatmap_request: HeatmapRequest, request: Request):
    try:
        client_id = get_client_id(request)
        kp_index = await get_safe_kp_index(client_id)

        # Segment cache by Kp index so storm simulations don't contaminate normal views
        cache_key = f"heatmap_{hash(str(heatmap_request.dict()))}_kp_{kp_index}"
        cached = await cache.get(cache_key)
        if cached:
            return cached

        heatmap = heatmap_generator.generate_heatmap(heatmap_request, kp_index)
        await cache.set(cache_key, heatmap, ttl=60)
        return heatmap
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/route")
async def calculate_route(route_request: RouteRequest, request: Request):
    try:
        client_id = get_client_id(request)
        kp_index = await get_safe_kp_index(client_id)
        sim_state = await get_simulation_state(client_id)
        scenario = "simulation" if sim_state["active"] else "normal"

        # Segment cache by Kp index and client
        cache_key = f"route_cache_{hashlib.md5(str(route_request.dict()).encode()).hexdigest()}_kp_{kp_index}"
        cached = await cache.get(cache_key)
        if cached:
            return cached

        routes = await router.find_routes(route_request, kp_index, scenario)
        await cache.set(cache_key, routes, ttl=300)
        return routes
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/imu/path")
async def calculate_imu_path(imu_request: IMUPathRequest, request: Request):
    try:
        client_id = get_client_id(request)
        route_request = RouteRequest(
            start=imu_request.start, end=imu_request.end, mode="safe"
        )
        kp_index = await get_safe_kp_index(client_id)
        sim_state = await get_simulation_state(client_id)
        scenario = "simulation" if sim_state["active"] else "normal"

        routes = await router.find_routes(route_request, kp_index, scenario)
        imu_path = routes.get("alternatives", {}).get("imu", {})

        return {
            "imu_path": imu_path.get("path", []),
            "distance_m": imu_path.get("distance_m", 0),
            "estimated_time_s": imu_path.get("estimated_time_s", 0),
            "risk_score": imu_path.get("total_risk_score", 0),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/simulation/gps-failure")
async def simulate_gps_failure(simulation: GPSFailureSimulation):
    try:
        result = storm_simulator.simulate_gps_failure(simulation)
        return {
            **result,
            "simulation_type": "gps_failure",
            "timestamp": datetime.utcnow().isoformat(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.websocket("/ws/imu")
async def imu_socket(websocket: WebSocket):
    await websocket.accept()

    client_id = websocket.query_params.get("client_id")

    if not client_id:
        await websocket.close()
        return

    imu_connections[client_id] = websocket

    try:
        while True:
            data = await websocket.receive_text()

            # Forward to map clients safely
            if client_id in map_connections:
                dead_conns = []
                for conn in map_connections[client_id]:
                    try:
                        await conn.send_text(data)
                    except Exception:
                        # If the connection closed while sending, mark it as dead
                        dead_conns.append(conn)

                # Clean up any disconnected clients so they don't crash the loop
                for dead in dead_conns:
                    if dead in map_connections[client_id]:
                        map_connections[client_id].remove(dead)

    except WebSocketDisconnect:
        imu_connections.pop(client_id, None)


@app.websocket("/ws/map")
async def map_socket(websocket: WebSocket):
    await websocket.accept()

    client_id = websocket.query_params.get("client_id")

    if not client_id:
        await websocket.close()
        return

    if client_id not in map_connections:
        map_connections[client_id] = []

    map_connections[client_id].append(websocket)

    try:
        while True:
            await asyncio.sleep(30)
    except WebSocketDisconnect:
        map_connections[client_id].remove(websocket)


@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    try:
        cache_status = await cache.ping()
        redis_status = await redis_client.ping()
        noaa_status = True
        try:
            await noaa_service.fetch_kp_index()
        except:
            noaa_status = False

        return HealthResponse(
            status=(
                "healthy"
                if cache_status and noaa_status and redis_status
                else "degraded"
            ),
            timestamp=datetime.utcnow(),
            services={
                "cache": cache_status,
                "redis": redis_status,
                "noaa": noaa_status,
            },
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail="Service unavailable")


@app.get("/status")
async def get_system_status(request: Request):
    client_id = get_client_id(request)
    sim_state = await get_simulation_state(client_id)
    return {
        "timestamp": datetime.utcnow().isoformat(),
        "simulation_active": sim_state["active"],
        "client_id_tracked": client_id,
    }


# --- REDIS PUB/SUB & WEBSOCKETS ---


async def broadcast_update(event_type: str, data: Dict[str, Any]):
    message = json.dumps(
        {"type": event_type, "data": data, "timestamp": datetime.utcnow().isoformat()},
        default=str,
    )
    await redis_client.publish("stellar_updates", message)


async def redis_pubsub_listener():
    pubsub = redis_client.pubsub()
    await pubsub.subscribe("stellar_updates")
    async for message in pubsub.listen():
        if message["type"] == "message":
            payload = message["data"]
            disconnected = []
            for connection in active_connections:
                try:
                    await connection.send_text(payload)
                except Exception:
                    disconnected.append(connection)
            for conn in disconnected:
                if conn in active_connections:
                    active_connections.remove(conn)


@app.websocket("/ws/updates")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_connections.append(websocket)
    try:
        while True:
            await asyncio.sleep(30)
            await websocket.send_json(
                {"type": "ping", "timestamp": datetime.utcnow().isoformat()}
            )
    except WebSocketDisconnect:
        active_connections.remove(websocket)
    except Exception as e:
        if websocket in active_connections:
            active_connections.remove(websocket)


@app.get("/metrics")
async def metrics():
    return FastAPIResponse(content=generate_latest(), media_type="text/plain")


# --- STARTUP / SHUTDOWN ---


@app.on_event("startup")
async def startup_event():
    asyncio.create_task(redis_pubsub_listener())
    await cache.set("api_startup", datetime.utcnow().isoformat(), ttl=3600)


@app.on_event("shutdown")
async def shutdown_event():
    await cache.clear()
    await redis_client.close()
