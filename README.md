# 🧭 NADR — Neuro Adaptive Dead Reckoning

**Navigation that doesn't stop when GPS does.**
NADR keeps vehicles on the map through tunnels, urban canyons, underground parking, and geomagnetic disturbances — by fusing GNSS with smartphone IMU sensors and AI-assisted dead reckoning.

---

## 🏆 Smart India Hackathon 2026

| | |
|---|---|
| **Problem Statement ID** | 26168 |
| **Problem Statement Title** | AI-ML based Intelligent Dead Reckoning system for seamless navigation |
| **Theme** | Smart Vehicles |
| **PS Category** | Software |
| **Team Name** | Root Access Only |

---

## 🎯 The Problem

GNSS/GPS signals fail or degrade in tunnels, underground parking, dense urban canyons, and during geomagnetic/solar storms. When that happens, most navigation apps either **freeze the map**, **snap the trajectory** to the wrong road, or drop guidance entirely — a real safety and reliability risk for drivers, delivery riders, and emergency responders who have no backup positioning system.

## 💡 Our Solution

NADR turns any smartphone into a resilient positioning device with **no extra hardware**:

### 1️⃣ Live GPS Tracking
- Uses the browser/device **Geolocation API** to track and render the vehicle's real, live position on the map as it moves.
- The map centers and follows the live fix automatically, without resetting zoom on every update — so it stays usable while walking or driving.

### 2️⃣ Space-Weather Risk Mapping
- Fetches real-time **Kp-index / geomagnetic data from NOAA**.
- Converts that into a live GPS-error risk heatmap, visualizing zones where GNSS accuracy is likely to degrade.

### 3️⃣ Intelligent Routing
- Calculates a **Normal Route** (shortest/actual path) and a **Storm-Safe Route** (lowest GNSS-risk path) using OSRM-based road-network routing combined with the risk model.

### 4️⃣ IMU Dead Reckoning (GPS-Denied Navigation)
- On activating **Live IMU Sensors**, the app switches from GPS to the phone's **accelerometer + gyroscope (compass heading)**.
- Speed is derived from linear acceleration and heading from device orientation, then integrated into lat/lon using a dead-reckoning position update — continuing navigation smoothly from the last known GPS fix even when GNSS is lost.
- Sensor data streams over **WebSockets** for real-time position updates on the map.

---

## 🛠️ Tech Stack

**Frontend**
- React 18 + Vite
- Tailwind CSS
- Leaflet / React-Leaflet (map rendering)
- Browser Geolocation, DeviceMotion & DeviceOrientation APIs (live GPS + IMU sensing)

**Backend**
- FastAPI (Python)
- WebSockets (real-time IMU/map sync)
- Redis (caching + pub/sub state)
- OSRM (road-network routing)
- NOAA Space Weather API (Kp-index / GNSS risk data)
- JWT-based session authentication

**Observability & Infra**
- Prometheus metrics (request latency, error rates)
- Docker + Docker Compose
- Nginx (reverse proxy, WebSocket upgrade handling)
- GitHub Actions CI (lint, format, tests)

---

## 🏗️ How It Works

```
GNSS Available → Normal GPS tracking + risk-aware routing
GNSS Lost      → IMU (accelerometer + gyroscope) dead reckoning
                  continues from the last known live position
GNSS Restored  → Live GPS tracking resumes seamlessly
```

---

## 🚦 Getting Started

### Local Development
```bash
git clone <repo-url>
cd NADR
docker-compose up --build
```

- **Frontend** → http://localhost:5173
- **Backend** → http://localhost:8000

### Manual Setup
```bash
# Backend
cd backend
pip install -r requirements.txt
python run.py

# Frontend
cd frontend
npm install
npm run dev
```

---

## 📊 Impact

- **Safety** — maintains navigation through tunnels/parking/urban canyons, reducing wrong-turn risk in GNSS-denied zones.
- **Accessibility** — works on any existing smartphone; no OBD-II or extra hardware required.
- **Economic** — prevents missed exits/delivery delays with zero added hardware cost.
- **Social** — safer routing for drivers, delivery riders, and emergency responders most exposed to GNSS blackout.

---

## 📄 References

- IO-VNBD Dataset — [GitHub](https://github.com/onyekpeu/IO-VNBD) · [Paper](https://doi.org/10.1016/j.dib.2021.106885)
- Deep-Learning-Based Vehicle Localization — [Paper](https://doi.org/10.3390/app11031270)
- Smartphone Vehicle Positioning using Sensor Fusion & Map Matching (2025) — [IEEE Xplore](https://ieeexplore.ieee.org/document/11031374)
- ISRO SIH 2026 Problem Statement PS-26168
- NASA Space Weather — https://science.nasa.gov/space-weather/
- ISRO Space-Weather Research — https://www.isro.gov.in/ISROCapturestheSignaturesoftheRecentSolarEruptiveEvents.html

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.