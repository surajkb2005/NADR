# backend/app/config.py
import os
from dotenv import load_dotenv
from typing import List

load_dotenv()


class Settings:
    # Application
    APP_NAME: str = "StellarRoute API"
    DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"

    # Server
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))

    # CORS – allow multiple origins from environment variable
    # Example: CORS_ORIGINS=http://localhost:3000,http://localhost:5173,https://yourdomain.com
    CORS_ORIGINS: List[str] = os.getenv(
        "CORS_ORIGINS",
        "http://localhost:3000,http://127.0.0.1:3000,http://localhost:5173,http://127.0.0.1:5173",
    ).split(",")

    # Redis
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379")

    # JWT / Auth
    SECRET_KEY: str = os.getenv(
        "SECRET_KEY", "a-default-secret-key-that-must-be-changed"
    )
    ALGORITHM: str = "HS256"
    SESSION_EXPIRY_SECONDS: int = 30 * 60  # 30 minutes

    # Email (SMTP)
    SMTP_SERVER: str = os.getenv("SMTP_SERVER", "smtp.gmail.com")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    EMAIL_ADDRESS: str = os.getenv("EMAIL_ADDRESS", "")
    EMAIL_PASSWORD: str = os.getenv("EMAIL_PASSWORD", "")

    # External APIs (NOAA)
    NOAA_BASE_URL: str = os.getenv("NOAA_BASE_URL", "https://services.swpc.noaa.gov")
    NOAA_TIMEOUT: float = 10.0


settings = Settings()
<<<<<<< HEAD
=======

# Security validation – must be done after settings is instantiated
if (
    settings.SECRET_KEY == "a-default-secret-key-that-must-be-changed"
    or len(settings.SECRET_KEY) < 16
):
    raise ValueError("SECRET_KEY is insecure! Set a strong secret in the environment.")
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
