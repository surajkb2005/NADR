import React, { useState, useEffect, useRef } from 'react'
import { Navigation2, MapPin, Target, Wifi, Smartphone } from 'lucide-react'
import MapComponent from './components/MapComponent'
import ControlPanel from './components/ControlPanel'
import RouteComparison from './components/RouteComparison'
import { stellarRouteAPI } from './services/api'
import { GPSSimulator, VehicleAnimator } from './utils/simulation'
import { DEMO_COORDINATES } from './utils/constants'
import LoginModal from './components/LoginModal';

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
  const [heatmapData, setHeatmapData] = useState(null)
  const [routes, setRoutes] = useState({})
  const [currentRouteMode, setCurrentRouteMode] = useState('normal')
  const [loading, setLoading] = useState(false)
  const [activePointType, setActivePointType] = useState(null)
  const [imuPath, setImuPath] = useState([])
  const [driftPath, setDriftPath] = useState([])

  // --- MAP STATE ---
  const [mapCenter, setMapCenter] = useState(DEMO_COORDINATES.Bengaluru)
  const [startPoint, setStartPoint] = useState(DEMO_COORDINATES.Bengaluru)
  const [endPoint, setEndPoint] = useState(DEMO_COORDINATES.Mumbai)
  const [mapBounds, setMapBounds] = useState(null)

  // --- SIMULATION STATE ---
  const [gpsActive, setGPSActive] = useState(true)
  const [vehicleMoving, setVehicleMoving] = useState(false)
  const [vehiclePosition, setVehiclePosition] = useState(null)
  const [useIMUNavigation, setUseIMUNavigation] = useState(false)

  // --- REFS ---
  const gpsSimulatorRef = useRef(null)
  const vehicleAnimatorRef = useRef(null)
  const imuNavigatorRef = useRef(null)
  const lastPositionRef = useRef(null)
  const geoWatchIdRef = useRef(null)

  // --- PERSISTENCE EFFECT ---
  useEffect(() => {
    const verifySession = async () => {
      try {
        const response = await stellarRouteAPI.checkAuthStatus();

        if (response.data.status === 'authenticated') {
          setIsLoggedIn(true);
          const emailName = response.data.user_email.split('@')[0];
          setUserName(emailName);

          // Sync safe display data to localStorage
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

    const userId = crypto.randomUUID();
    localStorage.setItem("client_id", userId);

    // Dynamically get API WS URL based on env or hostname
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsBaseUrl = `${wsProtocol}//${window.location.host}`;

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

  // --- LIVE GPS TRACKING EFFECT ---
useEffect(() => {
  if (!navigator.geolocation || realTimeMode) return; // IMU mode takes over movement

  geoWatchIdRef.current = navigator.geolocation.watchPosition(
    (pos) => {
      const coords = [pos.coords.latitude, pos.coords.longitude];
      setMapCenter(coords);
      setVehiclePosition(coords);
      lastPositionRef.current = coords;
    },
    (err) => console.error('Geolocation error:', err),
    { enableHighAccuracy: true, maximumAge: 1000, timeout: 10000 }
  );

  return () => {
    if (geoWatchIdRef.current !== null) {
      navigator.geolocation.clearWatch(geoWatchIdRef.current);
      geoWatchIdRef.current = null;
    }
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

      let boundsToUse = mapBounds;
      if (!boundsToUse) {
        boundsToUse = {
          _northEast: { lat: mapCenter[0] + 0.1, lng: mapCenter[1] + 0.1 },
          _southWest: { lat: mapCenter[0] - 0.1, lng: mapCenter[1] - 0.1 }
        };
      }
      fetchHeatmap(boundsToUse);
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
        north = bounds._northEast.lat; south = bounds._southWest.lat;
        east = bounds._northEast.lng; west = bounds._southWest.lng;
      }
      else if (typeof bounds.getNorth === 'function') {
        north = bounds.getNorth(); south = bounds.getSouth();
        east = bounds.getEast(); west = bounds.getWest();
      }

      if (isNaN(north)) return;
      const bboxList = [parseFloat(west), parseFloat(south), parseFloat(east), parseFloat(north)];
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

      if (data.alternatives?.normal?.path) {
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

  // --- MAP INTERACTION ---
  const handleMapClick = (coords) => {
    if (!activePointType) return;
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
    let minDist = Infinity; let closestIndex = 0
    path.forEach((point, index) => {
      const dist = Math.sqrt(Math.pow(point[0] - position[0], 2) + Math.pow(point[1] - position[1], 2))
      if (dist < minDist) { minDist = dist; closestIndex = index }
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
        imuNavigatorRef.current = new VehicleAnimator(targetPath.slice(closestIndex));
      }
      setUseIMUNavigation(true);
    } else {
      let targetPath = routes.normal?.path || [];

      if (targetPath.length > 0) {
        const closestIndex = findClosestPathIndex(currentPos, targetPath);
        vehicleAnimatorRef.current = new VehicleAnimator(targetPath.slice(closestIndex));
      }
      if (gpsSimulatorRef.current) gpsSimulatorRef.current.restoreGPS();
      setUseIMUNavigation(false);
      setDriftPath([]);
    }
  };

  const handleGPSFailureToggle = () => toggleSystemMode(gpsActive ? 'safe' : 'normal');

  const toggleRealTimeMode = () => {
    const newState = !realTimeMode;
    setRealTimeMode(newState);
    if (newState) {
      setVehicleMoving(false);
      setGPSActive(false);
      setUseIMUNavigation(true);
      setDriftPath([]);
      lastSensorTimeRef.current = 0;
      alert("Live Mode: Enabling local IMU controls!");
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
      case 'BLR_MUMBAI': start = DEMO_COORDINATES.Bengaluru; end = DEMO_COORDINATES.MUMBAI; break;
      case 'BLR_GOA': start = DEMO_COORDINATES.Bengaluru; end = DEMO_COORDINATES.GOA; break;
      case 'BLR_MANGALURU': start = DEMO_COORDINATES.Bengaluru; end = DEMO_COORDINATES.MANGALURU; break;
      default: return;
    }
    setStartPoint(start); setEndPoint(end); setVehiclePosition(start)
    calculateRoute(start, end, currentRouteMode)
  }

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
    <div className="relative min-h-screen bg-gradient-to-br from-gray-50 to-gray-100">

      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-primary/10 rounded-lg">
                <Navigation2 className="w-6 h-6 text-primary" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-gray-900">NADR</h1>
                <p className="text-sm text-gray-600">IMU Navigation system during GPS outages</p>
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
              {/* <button onClick={resetSimulation} className="px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg font-medium transition-colors">
                Reset Demo
              </button> */}
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

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">

          {/* Left Column */}
          <div className="lg:col-span-1 space-y-6">
            <div className="glass-card p-3 rounded-xl border-2 border-purple-500 shadow-sm bg-white">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Wifi className={`w-5 h-5 ${realTimeMode ? 'text-green-500 animate-pulse' : 'text-gray-400'}`} />
                  <div className="flex flex-col">
                    <span className="font-bold text-gray-800 text-sm leading-tight">Activate Live IMU Sensors</span>
                    <span className="text-[9px] text-gray-500"> Status: {realTimeMode ? 'Active' : 'Idle'}</span>
                  </div>
                </div>
                <button onClick={toggleRealTimeMode} className={`px-3 py-1.5 text-xs rounded-lg font-bold transition-all ${realTimeMode ? 'bg-purple-600 text-white hover:bg-purple-700' : 'bg-gray-200 text-gray-600 hover:bg-gray-300'}`}>
                  {realTimeMode ? 'ON' : 'OFF'}
                </button>
              </div>
            </div>
          </div>

          {/* Middle Column - Map */}
          <div className="lg:col-span-2">
            <div className="h-[600px] rounded-xl overflow-hidden shadow-xl relative">

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
              />
            </div>

            {/* Route Comparison */}
            <div className="mt-4">
              <RouteComparison routes={routes} currentMode={currentRouteMode} onSelectRoute={toggleSystemMode} compact={true} />
            </div>
          </div>

          {/* Right Column - Controls */}
          <div className="lg:col-span-1 space-y-6">
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
          </div>
        </div>
      </main>

      <footer className="mt-8 border-t bg-white py-6">
        <div className="container mx-auto px-4 text-center text-gray-600">
          <p className="font-medium">NADR - Project</p>
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