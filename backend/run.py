import logging
import sys
from pathlib import Path

import uvicorn

# Add project root to Python path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

# Import settings after path is set
from app.config import settings

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=[logging.StreamHandler(), logging.FileHandler("stellarroute.log")],
    )
    logger = logging.getLogger(__name__)
    logger.info("Starting StellarRoute backend server...")

    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info",
        access_log=True,
        proxy_headers=True,  # ← ADD THIS
        forwarded_allow_ips="*",  # ← ADD THIS (or set to your nginx container IP)
    )
