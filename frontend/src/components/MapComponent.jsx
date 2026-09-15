import React, { useEffect, useRef } from 'react'
import { MapContainer, TileLayer, Polyline, Polygon, Marker, Popup, useMap, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { RISK_LEVELS } from '../utils/constants'

// Custom vehicle icons
const createVehicleIcon = (gpsActive, useIMUNavigation) => {
  if (useIMUNavigation) {
    return L.divIcon({
      html: `
        <div class="relative">
          <div class="w-10 h-10 bg-purple-600 rounded-full flex items-center justify-center shadow-lg border-2 border-white">
            <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z" clip-rule="evenodd" />
            </svg>
          </div>
          <div class="absolute -top-1 -right-1 w-4 h-4 bg-purple-400 rounded-full animate-pulse"></div>
        </div>
      `,
      className: 'vehicle-marker imu',
      iconSize: [40, 40],
      iconAnchor: [20, 40]
    })
  }
  
  return L.divIcon({
    html: `
      <div class="relative">
        <div class="w-10 h-10 ${gpsActive ? 'bg-blue-600' : 'bg-red-600'} rounded-full flex items-center justify-center shadow-lg border-2 border-white">
          <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd" />
          </svg>
        </div>
        ${!gpsActive ? `
          <div class="absolute -top-1 -right-1 w-4 h-4 bg-red-500 rounded-full animate-pulse border border-white"></div>
          <div class="absolute -top-1 -right-1 w-4 h-4 bg-red-500 rounded-full animate-ping border border-white"></div>
        ` : ''}
      </div>
    `,
    className: 'vehicle-marker',
    iconSize: [40, 40],
    iconAnchor: [20, 40]
  })
}

// Custom start/end icons
const createPointIcon = (color, type) => {
  return L.divIcon({
    html: `
      <div class="relative">
        <div class="w-12 h-12 ${color} rounded-full flex items-center justify-center shadow-lg border-4 border-white transform hover:scale-110 transition-transform">
          <span class="text-white font-bold text-lg">${type === 'start' ? 'A' : 'B'}</span>
        </div>
        ${type === 'start' ? `
          <div class="absolute -bottom-1 left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-l-transparent border-r-transparent border-t-blue-500"></div>
        ` : `
          <div class="absolute -bottom-1 left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-l-transparent border-r-transparent border-t-green-500"></div>
        `}
      </div>
    `,
    className: 'point-marker',
    iconSize: [48, 48],
    iconAnchor: [24, 48]
  })
}

// Component to handle map clicks correctly
const MapClickHandler = ({ onMapClick }) => {
  useMapEvents({
    click: (e) => {
      const { lat, lng } = e.latlng
      onMapClick([lat, lng])
    },
  })
  return null
}

const MapController = ({ center, zoom, bounds }) => {
  const map = useMap()
  
  useEffect(() => {
    if (center) {
      map.setView(center, zoom)
    }
  }, [center, zoom, map])
  
  useEffect(() => {
    if (bounds) {
      map.fitBounds(bounds)
    }
  }, [bounds, map])
  
  return null
}

const MapComponent = ({
  chaosMode = false, 
  chaosIntensity = 1,
  center = [37.7749, -122.4194],
  zoom = 13,
  heatmapData = null,
  routes = {},
  vehiclePosition = null,
  startPoint = null,
  endPoint = null,
  gpsActive = true,
  imuPath = [],
  driftPath = [],
  useIMUNavigation = false,
  onMapClick = () => {},
  onBoundsChange = () => {}
}) => {
  const mapRef = useRef(null)

useEffect(() => {
  if (!mapRef.current) return;

  const map = mapRef.current;

  const updateBounds = () => {
    const bounds = map.getBounds();
    onBoundsChange([
      bounds.getWest(),
      bounds.getSouth(),
      bounds.getEast(),
      bounds.getNorth()
    ]);
  };

  map.on("moveend", updateBounds);

  return () => {
    map.off("moveend", updateBounds);
  };
}, []);

  // Render heatmap polygons
  const renderHeatmap = () => {
    if (!heatmapData?.features) return null
    
    return heatmapData.features.map((feature, index) => {
      const { geometry, properties } = feature
      const { risk_level, color, opacity } = properties
      
      return (
        <Polygon
          key={`heatmap-${index}`}
          positions={geometry.coordinates[0].map(coord => [coord[1], coord[0]])}
          pathOptions={{
            fillColor: color || RISK_LEVELS[risk_level]?.color || '#666',
            color: 'transparent',
            fillOpacity: opacity || 0.3,
            weight: 0
          }}
        >
          <Popup>
            <div className="p-2">
              <div className={`font-semibold ${RISK_LEVELS[risk_level]?.text}`}>
                {risk_level?.toUpperCase()} RISK ZONE
              </div>
              <div className="text-sm text-gray-600 mt-1">
                GPS Error: {properties.gps_error_min}m - {properties.gps_error_max}m
              </div>
              <div className="text-sm text-gray-600">
                Risk Score: {properties.risk_score}/100
              </div>
            </div>
          </Popup>
        </Polygon>
      )
    })
  }
  
  // Render routes
  const renderRoutes = () => {
    const elements = []
    
    // 1. Render DRIFTED Route (The "False" GPS path)
    if (routes.drifted?.path) {
      elements.push(
        <Polyline
          key="drifted-route"
          positions={routes.drifted.path}
          pathOptions={{
            color: '#ef4444', // Red
            weight: 4,
            opacity: 0.5,
            dashArray: '5, 10'
          }}
        >
          <Popup>
            <div className="p-2">
              <div className="font-semibold text-red-600">⚠️ SIMULATED GPS DRIFT</div>
              <div className="text-sm text-gray-600 mt-1">
                This is where the GPS <i>thinks</i> you are.
              </div>
              <div className="text-sm text-gray-600">
                Deviation caused by solar storm (Kp {routes.drifted.kp_index || 'High'}).
              </div>
            </div>
          </Popup>
        </Polyline>
      )
    }

    // 2. Render NORMAL Route (The "True" Road path)
    if (routes.normal?.path) {
      elements.push(
        <Polyline
          key="normal-route"
          positions={routes.normal.path}
          pathOptions={{
            color: '#2563eb', // Blue
            weight: 5,
            opacity: 0.8,
            dashArray: null
          }}
        >
          <Popup>
            <div className="p-2">
              <div className="font-semibold text-blue-600">NORMAL ROUTE (ACTUAL)</div>
              <div className="text-sm text-gray-600 mt-1">
                Distance: {(routes.normal.distance_m / 1000).toFixed(1)}km
              </div>
              <div className="text-sm text-gray-600">
                Risk: {routes.normal.total_risk_score?.toFixed(0) || 0}/100
              </div>
            </div>
          </Popup>
        </Polyline>
      )
    }
    
    // 3. Render SAFE Route
    if (routes.safe?.path) {
      elements.push(
        <Polyline
          key="safe-route"
          positions={routes.safe.path}
          pathOptions={{
            color: '#10b981', // Green
            weight: 5,
            opacity: 0.8,
            dashArray: '10, 10'
          }}
        >
          <Popup>
            <div className="p-2">
              <div className="font-semibold text-green-600">STORM-SAFE ROUTE</div>
              <div className="text-sm text-gray-600 mt-1">
                Distance: {(routes.safe.distance_m / 1000).toFixed(1)}km
              </div>
              <div className="text-sm text-gray-600">
                Risk: {routes.safe.total_risk_score?.toFixed(0) || 0}/100
              </div>
            </div>
          </Popup>
        </Polyline>
      )
    }
    
    // 4. Render IMU path (Purple)
    if (imuPath.length > 0 && useIMUNavigation) {
      elements.push(
        <Polyline
          key="imu-route"
          positions={imuPath}
          pathOptions={{
            color: '#8b5cf6',
            weight: 4,
            opacity: 0.7,
            dashArray: '5, 5'
          }}
        >
          <Popup>
            <div className="p-2">
              <div className="font-semibold text-purple-600">IMU NAVIGATION PATH</div>
              <div className="text-sm text-gray-600 mt-1">
                Using inertial navigation system
              </div>
              <div className="text-sm text-gray-600">
                Accuracy: ~10-20 meters
              </div>
            </div>
          </Popup>
        </Polyline>
      )
    }
    
    // 5. Render dynamic drift path history (Red dash)
    if (driftPath.length > 1 && !gpsActive) {
      elements.push(
        <Polyline
          key="drift-path"
          positions={driftPath}
          pathOptions={{
            color: '#ef4444',
            weight: 2,
            opacity: 0.6,
            dashArray: '3, 3'
          }}
        >
          <Popup>
            <div className="p-2">
              <div className="font-semibold text-red-600">GPS DRIFT TRAIL</div>
              <div className="text-sm text-gray-600 mt-1">
                Drift distance: ~{Math.round(driftPath.length * 15)}m
              </div>
              <div className="text-sm text-gray-600">
                Caused by geomagnetic interference
              </div>
            </div>
          </Popup>
        </Polyline>
      )
    }
    
    return elements
  }
  
  return (
    <div className="relative w-full h-full rounded-xl overflow-hidden shadow-xl">
      <MapContainer
        center={center}
        zoom={zoom}
        className="h-full w-full"
        ref={mapRef}
      >
        <TileLayer
  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  url={chaosMode 
    ? "https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png"
    : "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
  }
/>
        
        <MapController center={center} zoom={zoom} />
        <MapClickHandler onMapClick={onMapClick} />
        
        {/* Heatmap Overlay */}
        {renderHeatmap()}
        
        {/* Routes */}
        {renderRoutes()}
        
        {/* Start Point */}
        {startPoint && (
          <Marker 
            position={startPoint}
            icon={createPointIcon('bg-blue-500', 'start')}
            draggable={true}
          >
            <Popup>
              <div className="p-2">
                <div className="font-semibold text-blue-600">START POINT</div>
                <div className="text-sm text-gray-600">
                  {startPoint[0].toFixed(4)}, {startPoint[1].toFixed(4)}
                </div>
              </div>
            </Popup>
          </Marker>
        )}
        
        {/* End Point */}
        {endPoint && (
          <Marker 
            position={endPoint}
            icon={createPointIcon('bg-green-500', 'end')}
            draggable={true}
          >
            <Popup>
              <div className="p-2">
                <div className="font-semibold text-green-600">END POINT</div>
                <div className="text-sm text-gray-600">
                  {endPoint[0].toFixed(4)}, {endPoint[1].toFixed(4)}
                </div>
              </div>
            </Popup>
          </Marker>
        )}
        
        {/* Vehicle Marker */}
        {vehiclePosition && (
          <Marker 
            position={vehiclePosition}
            icon={createVehicleIcon(gpsActive, useIMUNavigation)}
          >
            <Popup>
              <div className="p-2">
                <div className="font-semibold">
                  {gpsActive ? '🚗 VEHICLE (GPS ACTIVE)' : 
                   useIMUNavigation ? '🧭 VEHICLE (IMU NAVIGATION)' : 
                   '⚠️ VEHICLE (GPS FAILED)'}
                </div>
                <div className="text-sm text-gray-600 mt-1">
                  Position: {vehiclePosition[0].toFixed(6)}, {vehiclePosition[1].toFixed(6)}
                </div>
              </div>
            </Popup>
          </Marker>
        )}
      </MapContainer>
      

      {/* Legend */}
      <div className="absolute bottom-0 left-0 glass-card p-2 rounded-lg backdrop-blur-sm max-w-xs z-[1000]">
        <div className="text-sm font-medium text-gray-700 mb-2">Map Legend</div>
        <div className="space-y-2 text-xs">
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-blue-500 rounded"></div>
            <span>Start Point (A)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 bg-green-500 rounded"></div>
            <span>End Point (B)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-0.5 bg-blue-600"></div>
            <span>Normal Route</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-0.5 bg-red-500 border-dashed border"></div>
            <span>Drifted (Simulated)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-0.5 bg-green-600 border-dashed border"></div>
            <span>Safe Route</span>
          </div>
          <div className="grid grid-cols-3 gap-1 mt-1">
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-risk-low opacity-30"></div>
              <span>Low</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-risk-medium opacity-30"></div>
              <span>Medium</span>
            </div>
            <div className="flex items-center gap-1">
              <div className="w-2 h-2 rounded-full bg-risk-high opacity-30"></div>
              <span>High</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default MapComponent