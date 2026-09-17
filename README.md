# 🌟 StellarRoute: Space-Weather Aware Navigation System

**Navigation that survives solar storms.** StellarRoute predicts GPS degradation from solar activity and provides continuous navigation through intelligent rerouting and sensor-fusion fallback.

[![Live Demo](https://img.shields.io/badge/demo-live-green)](https://stellar-route.me)
[![Code Quality Checks](https://github.com/varun99015/StellarRoute/actions/workflows/quality_check.yml/badge.svg)](https://github.com/varun99015/StellarRoute/actions)

## 🎯 The Problem
**Solar storms disrupt GPS signals**, causing navigation failures in aviation, logistics, and autonomous systems. **Current navigation systems have no solar-storm protection** — they fail completely or provide dangerously inaccurate positions during geomagnetic disturbances.

## 💡 Our Solution
StellarRoute provides **three layers of protection**:

### 1️⃣ Risk Mapping
- Fetches real-time space weather data from **NOAA/NASA**.
- Converts Kp-index, solar wind, and geomagnetic data into GPS error estimates.
- Generates live risk heatmaps showing areas of GPS degradation.

### 2️⃣ Intelligent Safe Routing
- **Space-Weather Aware Pathfinding**: A* pathfinding algorithm with risk-based penalties.
- **Dynamic Rerouting**: Calculates both "normal" (shortest) and "storm-safe" (lowest risk) routes in real-time as solar conditions change.

### 3️⃣ GPS Failure Resilience
- **IMU Fallback**: Simulated Inertial Measurement Unit (IMU) dead reckoning for continuous navigation during complete GPS outages.
- **Sub-second Sync**: Real-time state synchronization for multi-client chaos simulations using **Redis Pub/Sub**.

---

## 🛠️ Tech Stack

- **Frontend**: React, Vite, Tailwind CSS, Leaflet.js
- **Backend**: FastAPI (Python), OSRM (Open Source Routing Machine)
- **Real-time & Caching**: Redis (Pub/Sub & Caching)
- **Monitoring & Observability**: Prometheus, Grafana
- **Infrastructure**: Docker, Terraform, AWS (EC2, VPC, Security Groups)
- **DevOps**: GitHub Actions (CI/CD), Nginx (Reverse Proxy)

---

## 🏗️ Architecture & DevOps

StellarRoute is built as a containerized microservices architecture managed with a professional DevSecOps pipeline:

- **Infrastructure as Code (IaC)**: AWS environments (VPC, EC2, Security Groups) are provisioned and managed using **Terraform** for 100% reproducibility.
- **CI/CD Pipeline**: Automated quality checks (`black`, `flake8`, `pytest`) run in an ephemeral environment with a Redis service container for integration testing.
- **Automated Deployment**: On every push to the `Production` branch, Docker images are built with build-time environment injection, pushed to Docker Hub, and deployed via SSH to **AWS EC2** using Docker Compose.
- **Security**: Deployed behind an **Nginx reverse proxy** with **HttpOnly JWT** session management and automated firewall configuration.

### 📊 Monitoring & Observability
The system features a complete monitoring stack to track system health and algorithm performance:
- **Prometheus**: Scrapes real-time metrics from the FastAPI backend (request latency, A* processing time, error rates).
- **Grafana**: Visualizes system metrics through custom dashboards, allowing for sub-second monitoring of solar-storm impact on system performance.

---

## 🚦 Getting Started

### Local Development
1. Clone the repository.
2. Run `docker-compose up --build`.
3. Access the services:
   - **Frontend**: `http://localhost:5173`
   - **Backend**: `http://localhost:8000`
   - **Grafana**: `http://localhost:3001` (Default login: `admin`/`admin`)

### Infrastructure Setup
1. Navigate to the `/terraform` directory.
2. Run `terraform init` to initialize the providers.
3. Run `terraform apply` to deploy the full AWS stack.

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.
