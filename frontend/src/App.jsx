import React, { useState, useEffect, useRef } from 'react'
import { AlertTriangle, Navigation2, Satellite, MapPin, Target, Wifi, Smartphone } from 'lucide-react'
import MapComponent from './components/MapComponent'
import SpaceWeatherPanel from './components/SpaceWeatherPanel'
import ControlPanel from './components/ControlPanel'
import RouteComparison from './components/RouteComparison'
import SolarStormGlobe from './components/SolarStormGlobe'
import { stellarRouteAPI } from './services/api'
import { GPSSimulator, VehicleAnimator, IMUNavigator } from './utils/simulation'
import { DEMO_COORDINATES } from './utils/constants'
import LoginModal from './components/LoginModal';
<<<<<<< HEAD
import './styles/chaosEffects.css'; // We'll create this file
import { audioManager } from './utils/audioManager';

// --- FIREBASE IMPORTS ---
import { initializeApp } from "firebase/app";
import { getDatabase, ref, onValue } from "firebase/database";
import { firebaseConfig } from './firebaseConfig';

// Initialize Firebase
const firebaseApp = initializeApp(firebaseConfig);
const db = getDatabase(firebaseApp);
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523

import { BASE_URL } from './config';

function App() {
  // --- AUTHENTICATION STATE ---
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [userName, setUserName] = useState(null);
  const [authChecking, setAuthChecking] = useState(true);
  const [showLoginModal, setShowLoginModal] = useState(false);

  // --- REAL-TIME SENSOR STATE ---
  const [realTimeMode, setRealTimeMode] = useState(false);
  const lastSensorTimeRef = useRef(0); // Changed to ref to avoid stale closures

  // --- INTEGRATED IMU STATE ---
  const [imuEnabled, setImuEnabled] = useState(false);
  const [manualSpeed, setManualSpeed] = useState(0);
  const [deviceHeading, setDeviceHeading] = useState(0);
  const manualSpeedRef = useRef(0);
  const headingRef = useRef(0);

  // --- CORE STATE ---
  const [spaceWeather, setSpaceWeather] = useState(null)
  const [heatmapData, setHeatmapData] = useState(null)
  const [routes, setRoutes] = useState({})
  const [currentRouteMode, setCurrentRouteMode] = useState('normal')
  const [loading, setLoading] = useState(false)
  const [simulationMode, setSimulationMode] = useState(false)
  const [activePointType, setActivePointType] = useState(null)
  const [imuPath, setImuPath] = useState([])
  const [driftPath, setDriftPath] = useState([])

  // --- MAP STATE ---
  const [mapCenter] = useState(DEMO_COORDINATES.Bengaluru)
  const [startPoint, setStartPoint] = useState(DEMO_COORDINATES.Bengaluru)
  const [endPoint, setEndPoint] = useState(DEMO_COORDINATES.Mumbai)
  const [mapBounds, setMapBounds] = useState(null)

  // --- SIMULATION STATE ---
  const [gpsActive, setGPSActive] = useState(true)
  const [vehicleMoving, setVehicleMoving] = useState(false)
  const [vehiclePosition, setVehiclePosition] = useState(null)
  const [useIMUNavigation, setUseIMUNavigation] = useState(false)

  const [chaosMode, setChaosMode] = useState(false)
  const [chaosIntensity, setChaosIntensity] = useState(3)

  // --- REFS ---
  const gpsSimulatorRef = useRef(null)
  const vehicleAnimatorRef = useRef(null)
  const imuNavigatorRef = useRef(null)
  const lastPositionRef = useRef(null)

  // --- PERSISTENCE EFFECT ---
  useEffect(() => {
    const verifySession = async () => {
      try {
        const response = await stellarRouteAPI.checkAuthStatus();
<<<<<<< HEAD

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
        if (response.data.status === 'authenticated') {
          setIsLoggedIn(true);
          const emailName = response.data.user_email.split('@')[0];
          setUserName(emailName);
<<<<<<< HEAD

          // Sync safe display data to localStorage
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
          localStorage.setItem('stellar_isLoggedIn', 'true');
          localStorage.setItem('stellar_userName', emailName);
        }
      } catch (error) {
        setIsLoggedIn(false);
        setUserName(null);
        localStorage.removeItem('stellar_isLoggedIn');
        localStorage.removeItem('stellar_userName');
      } finally {
        setAuthChecking(false);
      }
    };
    verifySession();
  }, []);

  // --- REAL-TIME WEBSOCKET & SENSOR EFFECT ---
  useEffect(() => {
    if (!realTimeMode) return;

    const userId = "test123";
    localStorage.setItem("client_id", userId);

    // Dynamically get API WS URL based on env or hostname
    const apiBase = import.meta.env.VITE_API_URL || `http://${window.location.hostname}:8000`;
    const wsBaseUrl = apiBase.replace(/^http/, 'ws').replace(/\/api$/, '');

    const mapWs = new WebSocket(`${wsBaseUrl}/ws/map?client_id=${userId}`);
    const imuWs = new WebSocket(`${wsBaseUrl}/ws/imu?client_id=${userId}`);

    mapWs.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === "imu_update") {
        const newPos = calculateNewPosition(
          lastPositionRef.current?.[0] || startPoint[0],
          lastPositionRef.current?.[1] || startPoint[1],
          data,
          lastSensorTimeRef.current
        );

        setVehiclePosition([newPos.lat, newPos.lon]);
        lastPositionRef.current = [newPos.lat, newPos.lon];
        lastSensorTimeRef.current = newPos.timestamp;
      }
    };

    // 2. IMU Sender (Broadcasts our local sensor data)

    const sensorInterval = setInterval(() => {
      // --- APPLY FRICTION (Upgraded) ---
      if (manualSpeedRef.current > 0) {
        // 1. Multiplicative decay (slows down fast when going fast)
        manualSpeedRef.current *= 0.90;

        // 2. Linear drag (forces a complete stop when going slow)
        manualSpeedRef.current -= 1.0;

        // 3. Snap to 0 aggressively if it drops below 2%
        if (manualSpeedRef.current < 2.0) {
          manualSpeedRef.current = 0;
        }
      }

      // Sync the physical math to the React UI State
      setManualSpeed(Math.round(manualSpeedRef.current));

      // Broadcast to map
      if (imuWs.readyState === WebSocket.OPEN) {
        imuWs.send(JSON.stringify({
          type: "imu_update",
          speed: manualSpeedRef.current,
          heading: headingRef.current,
          timestamp: Date.now()
        }));
      }
    }, 200);

    mapWs.onopen = () => console.log("Map WS connected");
    imuWs.onopen = () => console.log("IMU WS connected");

    mapWs.onclose = () => {
      console.log("Map WS disconnected safely.");
    };

    return () => {
      mapWs.close();
      imuWs.close();
      clearInterval(sensorInterval);
    };
  }, [realTimeMode]);


  // --- SENSOR INTEGRATION LOGIC ---
  const requestSensorPermissions = async () => {
    try {
      if (typeof DeviceMotionEvent.requestPermission === 'function') {
        await DeviceMotionEvent.requestPermission();
        await DeviceOrientationEvent.requestPermission();
      }
      setImuEnabled(true);

      // 1. Start reading orientation (Compass)
      window.addEventListener("deviceorientation", e => {
        let correctedHeading;
        if (e.webkitCompassHeading !== undefined) {
          correctedHeading = Math.round(e.webkitCompassHeading);
        } else {
          correctedHeading = Math.round(360 - (e.alpha || 0)) % 360;
        }
        headingRef.current = correctedHeading;
        setDeviceHeading(correctedHeading);
      });

      // 2. Start reading motion (Accelerometer -> Speed)
      window.addEventListener("devicemotion", e => {
        // Get linear acceleration (excluding gravity)
        let accX = e.acceleration?.x || 0;
        let accY = e.acceleration?.y || 0;
        let accZ = e.acceleration?.z || 0;

        // Calculate the total physical force applied to the phone
        let magnitude = Math.sqrt(accX * accX + accY * accY + accZ * accZ);

        // Deadzone: Ignore tiny hand jitters (values under 1.0)
        if (magnitude > 1.0) {
          // Add the physical acceleration to our current speed
          let newSpeed = manualSpeedRef.current + (magnitude * 0.6); // Multiplier for feel
          manualSpeedRef.current = Math.min(40, newSpeed); // Cap max speed at 40
        }
      });

    } catch (err) {
      console.error("Sensor permission error:", err);
      alert("Please allow sensor access for Live Mode.");
    }
  };

  const handleSpeedChange = (delta) => {
    const newSpeed = Math.max(0, Math.min(40, manualSpeedRef.current + delta));
    manualSpeedRef.current = newSpeed;
    setManualSpeed(newSpeed);
  };


  // --- MATH HELPER FOR REAL-TIME ---
  const calculateNewPosition = (currentLat, currentLon, sensorData, prevTime) => {
    const R = 6371e3;
    const now = sensorData.timestamp;
    const dt = prevTime === 0 ? 0.1 : (now - prevTime) / 1000;

    if (dt > 2.0 || dt < 0) return { lat: currentLat, lon: currentLon, timestamp: now };

    const speed = (sensorData.speed || 0) / 3.6;
    const d = speed * dt;
    const brng = (sensorData.heading || 0) * Math.PI / 180;

    const lat1 = currentLat * Math.PI / 180;
    const lon1 = currentLon * Math.PI / 180;

    const lat2 = Math.asin(Math.sin(lat1) * Math.cos(d / R) +
      Math.cos(lat1) * Math.sin(d / R) * Math.cos(brng));

    const lon2 = lon1 + Math.atan2(Math.sin(brng) * Math.sin(d / R) * Math.cos(lat1),
      Math.cos(d / R) - Math.sin(lat1) * Math.sin(lat2));

    return {
      lat: lat2 * 180 / Math.PI,
      lon: lon2 * 180 / Math.PI,
      timestamp: now
    };
  }

<<<<<<< HEAD
  // --- FIREBASE LISTENER ---
  useEffect(() => {
    if (realTimeMode) {
      console.log("📡 Subscribing to Firebase vehicle_control...");
      const sensorRef = ref(db, 'vehicle_control');

      const unsubscribe = onValue(sensorRef, (snapshot) => {
        const data = snapshot.val();

        if (data && lastPositionRef.current) {
          const newPos = calculateNewPosition(
            lastPositionRef.current[0],
            lastPositionRef.current[1],
            data,
            lastSensorTime
          );

          setLastSensorTime(newPos.timestamp);
          setVehiclePosition([newPos.lat, newPos.lon]);
          lastPositionRef.current = [newPos.lat, newPos.lon];

          setDriftPath(prev => {
            const newPath = [...prev, [newPos.lat, newPos.lon]];
            if (newPath.length > 500) return newPath.slice(newPath.length - 500);
            return newPath;
          });
        }
      });

      return () => unsubscribe();
    }
  }, [realTimeMode, lastSensorTime]);

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
  // --- AUTHENTICATION HANDLERS ---
  const handleLoginSuccess = (userDisplayName) => {
    setIsLoggedIn(true);
    setUserName(userDisplayName);
    setShowLoginModal(false);
  };

  const handleLogout = async () => {
    try {
      await stellarRouteAPI.logout();
    } catch (error) {
      console.error("Logout failed:", error);
    } finally {
      setIsLoggedIn(false);
      setUserName(null);
      localStorage.clear();
    }
  };

  // --- INITIALIZATION ---
  useEffect(() => {
    fetchSpaceWeather()
    gpsSimulatorRef.current = new GPSSimulator(startPoint)
    imuNavigatorRef.current = new VehicleAnimator([startPoint])

    setTimeout(() => {
      calculateRoute(startPoint, endPoint, 'normal')
    }, 1000)
  }, [])

  // --- API CALLS ---
  const fetchSpaceWeather = async () => {
    try {
      setLoading(true)
      const response = await stellarRouteAPI.getCurrentSpaceWeather(mapCenter[0], mapCenter[1])
      setSpaceWeather(response.data)

      let boundsToUse = mapBounds;
      if (!boundsToUse) {
<<<<<<< HEAD
        const lat = mapCenter[0];
        const lon = mapCenter[1];
        boundsToUse = {
          _northEast: { lat: lat + 0.1, lng: lon + 0.1 },
          _southWest: { lat: lat - 0.1, lng: lon - 0.1 }
        };
      }
      fetchHeatmap(boundsToUse);

=======
        boundsToUse = {
          _northEast: { lat: mapCenter[0] + 0.1, lng: mapCenter[1] + 0.1 },
          _southWest: { lat: mapCenter[0] - 0.1, lng: mapCenter[1] - 0.1 }
        };
      }
      fetchHeatmap(boundsToUse);
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    } catch (error) {
      console.error('Error fetching space weather:', error)
    } finally {
      setLoading(false)
    }
  }

  const fetchHeatmap = async (bounds) => {
    try {
      if (!bounds) return;
      let north, south, east, west;
      if (bounds._northEast && bounds._southWest) {
<<<<<<< HEAD
        north = bounds._northEast.lat;
        south = bounds._southWest.lat;
        east = bounds._northEast.lng;
        west = bounds._southWest.lng;
      }
      else if (typeof bounds.getNorth === 'function') {
        north = bounds.getNorth();
        south = bounds.getSouth();
        east = bounds.getEast();
        west = bounds.getWest();
      }

      if (isNaN(north)) return;

      const bboxList = [
        parseFloat(west),
        parseFloat(south),
        parseFloat(east),
        parseFloat(north)
      ];

=======
        north = bounds._northEast.lat; south = bounds._southWest.lat;
        east = bounds._northEast.lng; west = bounds._southWest.lng;
      }
      else if (typeof bounds.getNorth === 'function') {
        north = bounds.getNorth(); south = bounds.getSouth();
        east = bounds.getEast(); west = bounds.getWest();
      }

      if (isNaN(north)) return;
      const bboxList = [parseFloat(west), parseFloat(south), parseFloat(east), parseFloat(north)];
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
      const response = await stellarRouteAPI.getHeatmap(bboxList);
      setHeatmapData(response.data);
    } catch (error) {
      console.error('Heatmap Error:', error);
    }
  }

  const calculateRoute = async (start, end, mode = 'normal') => {
    try {
      setLoading(true)
      const response = await stellarRouteAPI.calculateRoute(start, end, mode)
      const data = response.data

      setRoutes(data.alternatives || {})
      setCurrentRouteMode(mode)

      let routePath = data.route?.path || [start, end]

      if (mode === 'normal' && simulationMode && data.alternatives?.drifted?.path) {
        routePath = data.alternatives.drifted.path;
      } else if (data.alternatives?.normal?.path) {
        routePath = data.alternatives.normal.path;
      }

      if (!vehicleMoving) {
        vehicleAnimatorRef.current = new VehicleAnimator(routePath)
        setVehiclePosition(routePath[0])
        lastPositionRef.current = routePath[0]
      }

      if (start && end) {
        if (data.alternatives?.safe?.path) {
          setImuPath(data.alternatives.safe.path);
        } else {
          calculateIMUPath(start, end);
        }
      }
<<<<<<< HEAD

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    } catch (error) {
      console.error('Error calculating route:', error)
    } finally {
      setLoading(false)
    }
  }

  const calculateIMUPath = async (start, end) => {
    try {
      const response = await stellarRouteAPI.calculateRoute(start, end, 'safe')
      if (response.data.alternatives?.safe?.path) {
        setImuPath(response.data.alternatives.safe.path)
      }
    } catch (error) {
      console.error('Error calculating IMU path:', error)
    }
  }

  const simulateStorm = async (scenario) => {
    try {
      setLoading(true)
      const response = await stellarRouteAPI.simulateStorm(scenario, mapCenter[0], mapCenter[1])
      setSpaceWeather(response.data)
      setSimulationMode(true)
<<<<<<< HEAD

      if (startPoint && endPoint) {
        calculateRoute(startPoint, endPoint, currentRouteMode)
      }
=======
      if (startPoint && endPoint) calculateRoute(startPoint, endPoint, currentRouteMode)
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    } catch (error) { console.error(error); setLoading(false) }
  }

  const stopSimulation = async () => {
    try {
      await stellarRouteAPI.stopSimulation()
      setSimulationMode(false)
      fetchSpaceWeather()
    } catch (error) {
      console.error('Error stopping simulation:', error)
    }
  }

  // --- MAP INTERACTION ---
  const handleMapClick = (coords) => {
    if (!activePointType) return;
<<<<<<< HEAD

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    if (activePointType === 'start') {
      setStartPoint(coords)
      setVehiclePosition(coords)
      lastPositionRef.current = coords
      if (endPoint) calculateRoute(coords, endPoint, currentRouteMode)
    } else if (activePointType === 'end') {
      setEndPoint(coords)
      if (startPoint) calculateRoute(startPoint, coords, currentRouteMode)
    }
    setActivePointType(null)
  }

  const handleBoundsChange = (bounds) => {
    setMapBounds(bounds)
    fetchHeatmap(bounds)
  }

  const findClosestPathIndex = (position, path) => {
    if (!position || !path || path.length === 0) return 0
<<<<<<< HEAD
    let minDist = Infinity
    let closestIndex = 0

    path.forEach((point, index) => {
      const dist = Math.sqrt(
        Math.pow(point[0] - position[0], 2) +
        Math.pow(point[1] - position[1], 2)
      )
      if (dist < minDist) {
        minDist = dist
        closestIndex = index
      }
=======
    let minDist = Infinity; let closestIndex = 0
    path.forEach((point, index) => {
      const dist = Math.sqrt(Math.pow(point[0] - position[0], 2) + Math.pow(point[1] - position[1], 2))
      if (dist < minDist) { minDist = dist; closestIndex = index }
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    })
    return closestIndex
  }

  // --- MODE SWITCHERS ---
  const toggleSystemMode = (targetMode) => {
    const isSafeMode = targetMode === 'safe';
    setCurrentRouteMode(targetMode);

    const shouldGPSBeActive = !isSafeMode;
    setGPSActive(shouldGPSBeActive);

    const currentPos = vehiclePosition || startPoint;
    lastPositionRef.current = currentPos;

    if (!shouldGPSBeActive) {
      const targetPath = imuPath.length > 0 ? imuPath : (routes.safe?.path || routes.normal?.path || []);
      if (targetPath.length > 0) {
        const closestIndex = findClosestPathIndex(currentPos, targetPath);
<<<<<<< HEAD
        const remainingPath = targetPath.slice(closestIndex);
        imuNavigatorRef.current = new VehicleAnimator(remainingPath);
=======
        imuNavigatorRef.current = new VehicleAnimator(targetPath.slice(closestIndex));
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
      }
      setUseIMUNavigation(true);
    } else {
      let targetPath = routes.normal?.path || [];
      if (simulationMode && routes.drifted?.path && routes.drifted.path.length > 0) {
        targetPath = routes.drifted.path;
      }
      if (targetPath.length > 0) {
        const closestIndex = findClosestPathIndex(currentPos, targetPath);
<<<<<<< HEAD
        const remainingPath = targetPath.slice(closestIndex);
        vehicleAnimatorRef.current = new VehicleAnimator(remainingPath);
=======
        vehicleAnimatorRef.current = new VehicleAnimator(targetPath.slice(closestIndex));
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
      }
      if (gpsSimulatorRef.current) gpsSimulatorRef.current.restoreGPS();
      setUseIMUNavigation(false);
      setDriftPath([]);
    }
  };

<<<<<<< HEAD
  const handleGPSFailureToggle = () => {
    const newMode = gpsActive ? 'safe' : 'normal';
    toggleSystemMode(newMode);
  };
=======
  const handleGPSFailureToggle = () => toggleSystemMode(gpsActive ? 'safe' : 'normal');
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523

  const toggleRealTimeMode = () => {
    const newState = !realTimeMode;
    setRealTimeMode(newState);
    if (newState) {
      setVehicleMoving(false);
      setGPSActive(false);
      setUseIMUNavigation(true);
      setDriftPath([]);
<<<<<<< HEAD
      setLastSensorTime(0);
      alert("Real-Time Mode Active! Move your phone to navigate.");
=======
      lastSensorTimeRef.current = 0;
      alert("Live Mode: Enabling local IMU controls!");
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    } else {
      setGPSActive(true);
      setUseIMUNavigation(false);
    }
  };

  // --- ANIMATION LOOP ---
  useEffect(() => {
    let animationId
    const animate = () => {
      if (vehicleMoving && !realTimeMode) {
        let displayPosition;
        if (gpsActive) {
          if (vehicleAnimatorRef.current) displayPosition = vehicleAnimatorRef.current.update();
        } else {
          if (imuNavigatorRef.current) displayPosition = imuNavigatorRef.current.update();
        }

        if (displayPosition) {
          setVehiclePosition(displayPosition);
          const currentAnimator = gpsActive ? vehicleAnimatorRef.current : imuNavigatorRef.current;
          if (currentAnimator && !currentAnimator.isMoving) setVehicleMoving(false);
        }
        animationId = requestAnimationFrame(animate);
      }
    }

    if (vehicleMoving && !realTimeMode) {
      if (gpsActive) vehicleAnimatorRef.current?.start();
      else imuNavigatorRef.current?.start();
      animationId = requestAnimationFrame(animate)
    } else {
      vehicleAnimatorRef.current?.pause()
      imuNavigatorRef.current?.pause()
      if (animationId) cancelAnimationFrame(animationId)
    }
    return () => { if (animationId) cancelAnimationFrame(animationId) }
  }, [vehicleMoving, gpsActive, useIMUNavigation, realTimeMode])

  const resetSimulation = () => {
    setVehicleMoving(false)
    setRealTimeMode(false)
    setGPSActive(true)
    setUseIMUNavigation(false)
    setDriftPath([])
    setVehiclePosition(startPoint)
    stopSimulation()
<<<<<<< HEAD

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
    lastPositionRef.current = startPoint

    if (gpsSimulatorRef.current) gpsSimulatorRef.current.reset()
    if (vehicleAnimatorRef.current) {
      vehicleAnimatorRef.current.reset()
      const route = routes.normal?.path || [startPoint, endPoint]
      vehicleAnimatorRef.current = new VehicleAnimator(route)
    }
  }

  const useDemoRoute = (routeName) => {
    let start, end
    switch (routeName) {
      case 'BLR_MUMBAI': start = DEMO_COORDINATES.BENGALURU; end = DEMO_COORDINATES.MUMBAI; break;
      case 'BLR_GOA': start = DEMO_COORDINATES.BENGALURU; end = DEMO_COORDINATES.GOA; break;
      case 'BLR_MANGALURU': start = DEMO_COORDINATES.BENGALURU; end = DEMO_COORDINATES.MANGALURU; break;
      default: return;
    }
    setStartPoint(start); setEndPoint(end); setVehiclePosition(start)
    calculateRoute(start, end, currentRouteMode)
  }

<<<<<<< HEAD
  // --- CHAOS MODE AUDIO ---
  const playChaosAudio = () => {
    if (!chaosAudio || !chaosMode) return;

    // Create audio context
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();

    // Create siren sound
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    oscillator.frequency.setValueAtTime(800, audioContext.currentTime);
    oscillator.frequency.exponentialRampToValueAtTime(1200, audioContext.currentTime + 0.5);

    gainNode.gain.setValueAtTime(0.1, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.02, audioContext.currentTime + 0.5);

    oscillator.start();
    oscillator.stop(audioContext.currentTime + 0.5);

    // Play static randomly
    if (Math.random() > 0.7) {
      setTimeout(() => {
        const noise = audioContext.createBufferSource();
        const buffer = audioContext.createBuffer(1, audioContext.sampleRate * 0.5, audioContext.sampleRate);
        const data = buffer.getChannelData(0);

        for (let i = 0; i < buffer.length; i++) {
          data[i] = Math.random() * 2 - 1;
        }

        noise.buffer = buffer;
        const noiseGain = audioContext.createGain();
        noiseGain.gain.value = 0.05;

        noise.connect(noiseGain);
        noiseGain.connect(audioContext.destination);
        noise.start();
        noise.stop(audioContext.currentTime + 0.3);
      }, 300);
    }
  };

  // Effect for chaos audio
  useEffect(() => {
    if (chaosMode && chaosAudio) {
      const interval = setInterval(() => {
        playChaosAudio();
      }, 2000);

      return () => clearInterval(interval);
    }
  }, [chaosMode, chaosAudio]);

  useEffect(() => {
    if (chaosMode && chaosAudio) {
      audioManager.loadAudio('siren', '/src/assets/audio/emergency_siren.mp3');
      audioManager.play('siren');
      audioManager.setVolume('siren', 0.2);
    } else {
      audioManager.stop('siren');
    }
  }, [chaosMode, chaosAudio]);

=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
  if (authChecking) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-4 border-primary border-t-transparent rounded-full animate-spin"></div>
          <span className="font-medium text-gray-600">Verifying secure session...</span>
        </div>
      </div>
    );
  }

  return (
    <div className={`relative min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 ${chaosMode ? 'overflow-hidden chaos-mode' : ''}`}>

<<<<<<< HEAD
      {/* CHAOS OVERLAY EFFECTS */}
      {chaosMode && (
        <>
          {/* Red pulsing overlay */}
          <div className="fixed inset-0 pointer-events-none z-40">
            <div className={`absolute inset-0 ${chaosIntensity >= 3 ? 'bg-red-500/10 animate-pulse' : 'bg-red-500/5'}`}></div>

            {/* Screen shake effect */}
            <div className={`absolute inset-0 ${chaosIntensity >= 2 ? 'animate-shake' : ''}`}></div>

            {/* VHS scan lines */}
            <div className="absolute inset-0" style={{
              backgroundImage: `linear-gradient(
              to bottom,
              transparent 50%,
              rgba(0, 255, 255, 0.03) 50%
            )`,
              backgroundSize: '100% 4px',
              opacity: chaosIntensity >= 3 ? 0.3 : 0.1
            }}></div>

            {/* Emergency border */}
            <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-red-500 via-yellow-500 to-red-500 animate-flash"></div>
            <div className="absolute bottom-0 left-0 w-full h-1 bg-gradient-to-r from-red-500 via-yellow-500 to-red-500 animate-flash"></div>

            {/* Glitch particles */}
            {[...Array(chaosIntensity * 5)].map((_, i) => (
              <div
                key={i}
                className="absolute w-1 h-1 bg-red-500 rounded-full animate-ping"
                style={{
                  left: `${Math.random() * 100}%`,
                  top: `${Math.random() * 100}%`,
                  animationDelay: `${Math.random() * 2}s`,
                  opacity: Math.random() * 0.5
                }}
              />
            ))}
          </div>

          {/* Emergency Banner */}
          <div className={`relative z-50 ${chaosIntensity >= 4 ? 'animate-shake-hard' : 'animate-shake'}`}>
            <div className="bg-gradient-to-r from-red-600 via-red-700 to-red-600 text-yellow-300 text-center p-3 text-xl font-black border-y-4 border-yellow-400 animate-flash chaos-text">
              <div className="flex items-center justify-center gap-4">
                <span className="text-2xl">🚨</span>
                <span>SOLAR ARMAGEDDON! Kp: OVER 9000!</span>
                <span className="text-2xl">🚨</span>
              </div>
              <div className="text-sm text-yellow-200 mt-1">
                ANNOUNCE WINNERS SOON!
              </div>
            </div>
          </div>

          {/* Breaking News Ticker */}
          {chaosIntensity >= 2 && (
            <div className="w-full overflow-hidden bg-red-900 border-b-2 border-yellow-400 h-8 relative z-40">
              <div className="flex items-center h-full">
                <div className="px-4 py-1 bg-red-700 text-white font-bold whitespace-nowrap text-sm">
                  🚨 BREAKING
                </div>
                <div className="flex-1 overflow-hidden relative h-full">
                  <div className="absolute whitespace-nowrap text-yellow-300 font-semibold text-sm flex items-center h-full animate-ticker">
                    GPS SYSTEMS FAILING WORLDWIDE • SOLAR FLARE IMPACT MAXIMUM • EMERGENCY PROTOCOLS ACTIVATED • NAVIGATION COMPROMISED • SYSTEM CRITICAL
                  </div>
                </div>
                <div className="px-4 py-1 bg-red-700 text-white font-bold whitespace-nowrap text-sm">
                  🚨
                </div>
              </div>
            </div>
          )}
        </>
      )}
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-primary/10 rounded-lg">
                <Navigation2 className="w-6 h-6 text-primary" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-gray-900">StellarRoute</h1>
                <p className="text-sm text-gray-600">Space-weather aware navigation system</p>
              </div>
            </div>

            <div className="flex items-center gap-4">
              {isLoggedIn ? (
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-gray-700">Hi, {userName || 'User'}</span>
                  <button onClick={handleLogout} className="px-3 py-1 bg-red-500 hover:bg-red-600 text-white rounded-lg text-sm transition-colors">
                    Logout
                  </button>
                </div>
              ) : (
                <button onClick={() => setShowLoginModal(true)} className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium transition-colors">
                  Login
                </button>
              )}
              <button onClick={resetSimulation} className="px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg font-medium transition-colors">
                Reset Demo
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* POINT SELECTION MODAL */}
      {activePointType === 'selecting' && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[2000] animate-fade-in">
          <div className="bg-white p-6 rounded-xl shadow-2xl max-w-md w-full mx-4">
            <h3 className="text-lg font-bold mb-4 text-gray-800">Set Point on Map</h3>
            <div className="grid grid-cols-2 gap-4 mb-6">
              <button onClick={() => setActivePointType('start')} className="p-4 border-2 border-blue-100 bg-blue-50 rounded-xl hover:bg-blue-100 transition-all group">
                <div className="flex flex-col items-center gap-2">
                  <div className="p-3 bg-blue-500 rounded-full text-white shadow-md"><MapPin className="w-6 h-6" /></div>
                  <span className="font-semibold text-blue-700">Set Start</span>
                </div>
              </button>
              <button onClick={() => setActivePointType('end')} className="p-4 border-2 border-green-100 bg-green-50 rounded-xl hover:bg-green-100 transition-all group">
                <div className="flex flex-col items-center gap-2">
                  <div className="p-3 bg-green-500 rounded-full text-white shadow-md"><Target className="w-6 h-6" /></div>
                  <span className="font-semibold text-green-700">Set End</span>
                </div>
              </button>
            </div>
            <button onClick={() => setActivePointType(null)} className="w-full py-3 bg-gray-100 text-gray-700 font-medium rounded-lg hover:bg-gray-200">Cancel</button>
          </div>
        </div>
      )}
<<<<<<< HEAD

      {/* SELECTION INDICATOR */}
      {(activePointType === 'start' || activePointType === 'end') && (
        <div className="fixed top-24 left-1/2 transform -translate-x-1/2 z-[2000] bg-gray-900/90 text-white px-6 py-3 rounded-full shadow-lg backdrop-blur-sm animate-bounce-subtle flex items-center gap-3">
          {activePointType === 'start' ? <MapPin className="w-5 h-5 text-blue-400" /> : <Target className="w-5 h-5 text-green-400" />}
          <span className="font-medium">Click on map to set {activePointType === 'start' ? 'Start Point' : 'End Point'}</span>
          <button onClick={() => setActivePointType(null)} className="ml-2 p-1 hover:bg-white/20 rounded-full">✕</button>
        </div>
      )}
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">

<<<<<<< HEAD
          {/* Left Column - Weather and Globe */}
          <div className="lg:col-span-1 space-y-6">
            {/* 1. LIVE SENSOR TOGGLE - Compact version */}
=======
          {/* Left Column */}
          <div className="lg:col-span-1 space-y-6">
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
            <div className="glass-card p-3 rounded-xl border-2 border-purple-500 shadow-sm bg-white">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Wifi className={`w-5 h-5 ${realTimeMode ? 'text-green-500 animate-pulse' : 'text-gray-400'}`} />
                  <div className="flex flex-col">
                    <span className="font-bold text-gray-800 text-sm leading-tight">Live Sensors</span>
                    <span className="text-[9px] text-gray-500">Firebase: {realTimeMode ? 'Active' : 'Idle'}</span>
                  </div>
                </div>
                <button onClick={toggleRealTimeMode} className={`px-3 py-1.5 text-xs rounded-lg font-bold transition-all ${realTimeMode ? 'bg-purple-600 text-white hover:bg-purple-700' : 'bg-gray-200 text-gray-600 hover:bg-gray-300'}`}>
                  {realTimeMode ? 'ON' : 'OFF'}
                </button>
              </div>
            </div>

<<<<<<< HEAD
            {/* 2. SOLAR STORM 3D GLOBE - Smaller */}
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
            <div className="h-[300px] rounded-xl overflow-hidden shadow-lg border border-gray-200 bg-black relative">
              <SolarStormGlobe kpIndex={spaceWeather?.kp_index || 2} compact={true} />
            </div>

<<<<<<< HEAD
            {/* 3. SPACE WEATHER PANEL - Compact */}
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
            <SpaceWeatherPanel
              spaceWeather={spaceWeather}
              onRefresh={fetchSpaceWeather}
              onSimulate={simulateStorm}
              simulationMode={simulationMode}
              loading={loading}
              compact={true}
            />
          </div>

          {/* Middle Column - Map */}
          <div className="lg:col-span-2">
            <div className="h-[600px] rounded-xl overflow-hidden shadow-xl relative">
<<<<<<< HEAD
              {activePointType === 'selecting' && <div className="absolute inset-0 bg-black/10 z-10 pointer-events-none" />}
=======

              {/* === EMBEDDED IMU OVERLAY CONTROLS === */}
              {realTimeMode && (
                <div className="absolute top-4 right-4 z-[1000] bg-white/95 backdrop-blur-md p-4 rounded-xl shadow-2xl border border-purple-200 w-64 animate-fade-in">
                  <h3 className="font-bold text-[13px] text-purple-800 mb-3 flex items-center justify-between">
                    <span className="flex items-center gap-2"><Smartphone className="w-4 h-4" /> IMU Dashboard</span>
                    <span className="relative flex h-2 w-2">
                      <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                      <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
                    </span>
                  </h3>

                  {!imuEnabled ? (
                    <button onClick={requestSensorPermissions} className="w-full bg-blue-600 hover:bg-blue-700 text-white text-xs font-bold py-2.5 px-4 rounded-lg transition-colors mb-2 shadow-sm">
                      Enable Compass/Gyro
                    </button>
                  ) : (
                    <div className="text-xs font-medium text-green-700 mb-3 bg-green-50 py-1.5 px-2 rounded border border-green-200 flex justify-center">
                      Sensors Connected & Reading
                    </div>
                  )}

                  {/* <div className="space-y-3 mt-1">
                    <div className="bg-gray-50 p-3 rounded-lg border border-gray-200">
                      <div className="text-[10px] uppercase font-bold text-gray-500 mb-2">Simulated Speed (%)</div>
                      <div className="flex items-center justify-between gap-3">
                        <button onClick={() => handleSpeedChange(-10)} className="w-10 h-8 flex items-center justify-center bg-red-100 hover:bg-red-200 text-red-700 rounded font-bold transition-colors">⬇</button>
                        <span className="font-mono font-bold text-gray-800 text-lg">{manualSpeed}</span>
                        <button onClick={() => handleSpeedChange(10)} className="w-10 h-8 flex items-center justify-center bg-green-100 hover:bg-green-200 text-green-700 rounded font-bold transition-colors">⬆</button>
                      </div>
                    </div>

                    <div className="bg-gray-50 p-3 rounded-lg border border-gray-200 text-center">
                      <div className="text-[10px] uppercase font-bold text-gray-500 mb-1">Rotational Heading (α)</div>
                      <div className="font-mono font-bold text-blue-600 text-2xl">{deviceHeading}°</div>
                    </div>
                  </div> */}
                </div>
              )}

>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
              <MapComponent
                center={mapCenter}
                zoom={12}
                heatmapData={heatmapData}
                routes={routes}
                vehiclePosition={vehiclePosition}
                startPoint={startPoint}
                endPoint={endPoint}
                gpsActive={gpsActive}
                imuPath={imuPath}
                driftPath={driftPath}
                useIMUNavigation={useIMUNavigation}
                onMapClick={handleMapClick}
                onBoundsChange={handleBoundsChange}
                chaosMode={chaosMode}
                chaosIntensity={chaosIntensity}
              />
            </div>

<<<<<<< HEAD
            {/* Status Bar below map */}
            <div className="mt-4 p-3 bg-white rounded-lg shadow-sm">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <div className={`px-2 py-1 rounded-full text-xs font-medium ${gpsActive ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
                    {gpsActive ? 'GPS Active' : 'IMU Active'}
                  </div>
                  {realTimeMode && <div className="px-2 py-1 rounded-full text-xs font-medium bg-purple-100 text-purple-800">Live Mode</div>}
                </div>
                <div className="text-xs text-gray-600">
                  {vehiclePosition && <span>Position: {vehiclePosition[0].toFixed(6)}, {vehiclePosition[1].toFixed(6)}</span>}
                </div>
              </div>
            </div>

            {/* Route Comparison below map */}
            <div className="mt-4">
              <RouteComparison
                routes={routes}
                currentMode={currentRouteMode}
                onSelectRoute={toggleSystemMode}
                compact={true}
              />
=======
            {/* Route Comparison */}
            <div className="mt-4">
              <RouteComparison routes={routes} currentMode={currentRouteMode} onSelectRoute={toggleSystemMode} compact={true} />
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
            </div>
          </div>

          {/* Right Column - Controls */}
          <div className="lg:col-span-1 space-y-6">
<<<<<<< HEAD
            {/* Control Panel - Full height */}
=======
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
            <div className="h-full">
              <ControlPanel
                routeMode={currentRouteMode}
                onRouteModeChange={toggleSystemMode}
                gpsActive={gpsActive}
                onGPSFailureToggle={handleGPSFailureToggle}
                vehicleMoving={vehicleMoving}
                onVehicleMoveToggle={() => setVehicleMoving(!vehicleMoving)}
                onReset={resetSimulation}
                onSetPoints={() => setActivePointType('selecting')}
                onClearPoints={() => { setStartPoint(null); setEndPoint(null); setRoutes({}); setVehiclePosition(null); setDriftPath([]) }}
                startPoint={startPoint}
                endPoint={endPoint}
                onUseDemoRoute={useDemoRoute}
                compact={false}
              />
            </div>
<<<<<<< HEAD

            {/* Additional info/status card */}
            {/* <div className="bg-gradient-to-br from-blue-50 to-indigo-50 rounded-xl p-4 border border-blue-200">
        <h3 className="font-bold text-gray-800 mb-2 flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" />
          System Status
        </h3>
        <div className="space-y-2">
          <div className="flex justify-between items-center">
            <span className="text-sm text-gray-600">GPS Signal</span>
            <span className={`text-xs font-medium px-2 py-1 rounded ${gpsActive ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
              {gpsActive ? 'Strong' : 'Weak'}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-sm text-gray-600">Weather Risk</span>
            <span className={`text-xs font-medium px-2 py-1 rounded ${
              spaceWeather?.risk_level === 'high' ? 'bg-red-100 text-red-800' :
              spaceWeather?.risk_level === 'medium' ? 'bg-yellow-100 text-yellow-800' :
              'bg-green-100 text-green-800'
            }`}>
              {spaceWeather?.risk_level || 'Low'}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-sm text-gray-600">Vehicle</span>
            <span className="text-xs font-medium text-gray-700">
              {vehicleMoving ? 'Moving' : 'Stopped'}
            </span>
          </div>
        </div>
      </div> */}

            {/* Demo Routes Quick Select
      <div className="bg-white rounded-xl p-4 shadow-sm border">
        <h3 className="font-bold text-gray-800 mb-3">Quick Routes</h3>
        <div className="grid grid-cols-2 gap-2">
          <button 
            onClick={() => useDemoRoute('SF_OAKLAND')}
            className="p-2 bg-blue-50 hover:bg-blue-100 rounded-lg text-xs font-medium text-blue-700 transition-colors"
          >
            SF → Oakland
          </button>
          <button 
            onClick={() => useDemoRoute('SF_BERKELEY')}
            className="p-2 bg-green-50 hover:bg-green-100 rounded-lg text-xs font-medium text-green-700 transition-colors"
          >
            SF → Berkeley
          </button>
          <button 
            onClick={() => useDemoRoute('SF_SAN_JOSE')}
            className="p-2 bg-purple-50 hover:bg-purple-100 rounded-lg text-xs font-medium text-purple-700 transition-colors"
          >
            SF → San Jose
          </button>
          <button 
            onClick={resetSimulation}
            className="p-2 bg-gray-50 hover:bg-gray-100 rounded-lg text-xs font-medium text-gray-700 transition-colors"
          >
            Reset All
          </button>
        </div>
      </div> */}
          </div>
        </div>

        {/* CHAOS ERROR POPUPS */}
        {chaosMode && chaosIntensity >= 3 && (
          <>
            {[...Array(Math.min(chaosIntensity, 3))].map((_, i) => (
              <div
                key={i}
                className="fixed z-[10000] p-3 bg-red-900/90 border-2 border-red-600 rounded-lg shadow-lg max-w-xs animate-fade-in"
                style={{
                  left: `${20 + (i * 25)}%`,
                  top: `${30 + (i * 15)}%`,
                  animationDelay: `${i * 0.5}s`
                }}
              >
                <div className="flex items-start gap-2">
                  <AlertTriangle className="w-5 h-5 text-red-300 mt-0.5 flex-shrink-0" />
                  <div>
                    <div className="font-bold text-red-200 text-sm mb-1">
                      SYSTEM ERROR
                    </div>
                    <div className="text-xs text-white">
                      {[
                        "GPS SIGNAL LOST: Solar interference",
                        "IMU CALIBRATION FAILING",
                        "SATELLITE NETWORK COMPROMISED",
                        "NAVIGATION ACCURACY DEGRADED",
                        "SYSTEM OVERLOAD DETECTED"
                      ][i]}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </>
        )}

        {/* SYSTEM STATUS HUD */}
        {chaosMode && (
          <div className="fixed bottom-4 right-4 z-[9999] w-48 bg-black/80 backdrop-blur-sm rounded-lg p-3 border border-red-500">
            <div className="text-center text-xs text-red-400 font-bold mb-2">
              SYSTEM STATUS
            </div>

            <div className="space-y-2">
              <div>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-gray-300">GPS SIGNAL</span>
                  <span className={`font-bold ${chaosIntensity >= 4 ? 'text-red-400' : 'text-yellow-400'}`}>
                    {chaosIntensity >= 4 ? 'FAILED' : 'UNSTABLE'}
                  </span>
                </div>
                <div className="h-1.5 bg-gray-800 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-red-500 transition-all duration-300"
                    style={{ width: `${100 - (chaosIntensity * 20)}%` }}
                  />
                </div>
              </div>

              <div>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-gray-300">SYSTEM LOAD</span>
                  <span className="text-red-400 font-bold">{chaosIntensity * 20}%</span>
                </div>
                <div className="h-1.5 bg-gray-800 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-yellow-500 transition-all duration-300"
                    style={{ width: `${chaosIntensity * 20}%` }}
                  />
                </div>
              </div>

              <div className="text-center text-[10px] text-gray-400 mt-2">
                CHAOS LEVEL: {chaosIntensity}/5
              </div>
            </div>
          </div>
        )}

        {/* FAKE COUNTDOWN TIMER */}
        {chaosMode && chaosIntensity >= 4 && (
          <div className="fixed top-24 right-4 z-[9999] animate-pulse">
            <div className="p-3 bg-red-900/90 border-2 border-red-600 rounded-lg text-center min-w-[140px]">
              <div className="text-xs text-gray-300 mb-1">SYSTEM FAILURE IN</div>
              <div className="text-2xl font-mono font-bold text-red-400 mb-2">01:{String(59 - (new Date().getSeconds())).padStart(2, '0')}</div>
              <div className="text-xs text-red-300">TAKE COVER!</div>
            </div>
          </div>
        )}
      </main>

      <footer className="mt-8 border-t bg-white py-6">
        <div className="container mx-auto px-4">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="text-gray-600"><p className="font-medium">StellarRoute - Hackathon Project</p></div>
            <div className="flex items-center gap-4">
              <button onClick={() => window.open(`${BASE_URL}/docs`, '_blank')} className="text-sm text-primary hover:text-primary/80">API Documentation</button>
            </div>
          </div>
=======
          </div>
        </div>
      </main>

      <footer className="mt-8 border-t bg-white py-6">
        <div className="container mx-auto px-4 text-center text-gray-600">
          <p className="font-medium">StellarRoute - Hackathon Project</p>
>>>>>>> d4da3e93441bb6f4d123f06ba8a01e1893783523
        </div>
      </footer>

      {loading && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white p-6 rounded-xl shadow-2xl">
            <div className="flex items-center gap-3">
              <div className="w-5 h-5 border-2 border-primary border-t-transparent rounded-full animate-spin"></div>
              <span className="font-medium">Loading...</span>
            </div>
          </div>
        </div>
      )}

      {showLoginModal && <LoginModal onClose={() => setShowLoginModal(false)} onSuccess={handleLoginSuccess} />}
    </div>
  )
}

export default App