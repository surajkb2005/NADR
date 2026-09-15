import React from 'react'
import {
  Navigation,
  Shield,
  Satellite,
  WifiOff,
  Play,
  Pause,
  RotateCcw,
  MapPin,
  Target,
  Trash2,
  Navigation2,
  AlertTriangle,
  Zap
} from 'lucide-react'
import { DEMO_COORDINATES } from '../utils/constants'

const ControlPanel = ({
  routeMode,
  onRouteModeChange,
  gpsActive,
  onGPSFailureToggle,
  vehicleMoving,
  onVehicleMoveToggle,
  onReset,
  onSetPoints,
  onClearPoints,
  startPoint,
  endPoint,
  onUseDemoRoute
}) => {
  return (
    <div className="glass-card p-6 rounded-xl">
      <div className="flex items-center gap-2 mb-6">
        <Navigation2 className="w-5 h-5 text-primary" />
        <h2 className="text-xl font-bold text-gray-800">Navigation Controls</h2>
      </div>

      {/* Quick Actions */}
      <div className="mb-6">
        <div className="text-sm font-medium text-gray-700 mb-3">Quick Actions</div>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={onSetPoints}
            className="p-3 rounded-lg bg-gradient-to-r from-blue-50 to-blue-100 border border-blue-200 hover:from-blue-100 hover:to-blue-200 transition-all flex items-center justify-center gap-2"
          >
            <MapPin className="w-4 h-4 text-blue-600" />
            <span className="font-medium text-blue-700">Set Points</span>
          </button>

          <button
            onClick={onClearPoints}
            disabled={!startPoint && !endPoint}
            className="p-3 rounded-lg bg-gradient-to-r from-gray-50 to-gray-100 border border-gray-200 hover:from-gray-100 hover:to-gray-200 transition-all flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Trash2 className="w-4 h-4 text-gray-600" />
            <span className="font-medium text-gray-700">Clear</span>
          </button>
        </div>
      </div>

      {/* Route Mode Selection */}
      <div className="mb-6">
        <div className="text-sm font-medium text-gray-700 mb-3">Route Optimization</div>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => onRouteModeChange('normal')}
            className={`p-4 rounded-lg border-2 transition-all flex flex-col items-center justify-center ${routeMode === 'normal' ? 'border-primary bg-gradient-to-b from-blue-50 to-blue-100 shadow-sm' : 'border-gray-200 bg-white hover:border-gray-300 hover:bg-gray-50'}`}
          >
            <Navigation className={`w-6 h-6 mb-2 ${routeMode === 'normal' ? 'text-primary' : 'text-gray-500'}`} />
            <span className={`font-medium ${routeMode === 'normal' ? 'text-primary' : 'text-gray-700'}`}>
              Normal
            </span>
            <span className="text-xs text-gray-500 mt-1">Fastest route</span>
          </button>

          <button
            onClick={() => onRouteModeChange('safe')}
            className={`p-4 rounded-lg border-2 transition-all flex flex-col items-center justify-center ${routeMode === 'safe' ? 'border-green-500 bg-gradient-to-b from-green-50 to-green-100 shadow-sm' : 'border-gray-200 bg-white hover:border-gray-300 hover:bg-gray-50'}`}
          >
            <Shield className={`w-6 h-6 mb-2 ${routeMode === 'safe' ? 'text-green-600' : 'text-gray-500'}`} />
            <span className={`font-medium ${routeMode === 'safe' ? 'text-green-600' : 'text-gray-700'}`}>
              Storm-Safe
            </span>
            <span className="text-xs text-gray-500 mt-1">Avoids high risk</span>
          </button>
        </div>
      </div>

      {/* GPS & Simulation Controls */}
      <div className="mb-6">
        <div className="text-sm font-medium text-gray-700 mb-3">GPS Simulation</div>
        <div className="space-y-3">
          <div className="bg-gradient-to-r from-gray-50 to-gray-100 p-4 rounded-lg border border-gray-200">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <Satellite className={`w-5 h-5 ${gpsActive ? 'text-green-600' : 'text-red-500'}`} />
                <span className={`font-medium ${gpsActive ? 'text-green-700' : 'text-red-700'}`}>
                  {gpsActive ? 'GPS Active' : 'GPS Failed'}
                </span>
              </div>
              <div className={`px-2 py-1 text-xs rounded-full ${gpsActive ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
                {gpsActive ? 'Normal' : 'IMU Mode'}
              </div>
            </div>

            <button
              onClick={onGPSFailureToggle}
              className={`w-full py-3 rounded-lg font-medium flex items-center justify-center gap-2 transition-all ${gpsActive ? 'bg-gradient-to-r from-red-100 to-red-200 text-red-700 hover:from-red-200 hover:to-red-300' : 'bg-gradient-to-r from-green-100 to-green-200 text-green-700 hover:from-green-200 hover:to-green-300'}`}
            >
              <WifiOff className="w-4 h-4" />
              {gpsActive ? 'Simulate GPS Failure' : 'Restore GPS Signal'}
            </button>

            <div className="text-xs text-gray-500 mt-3">
              {gpsActive
                ? 'GPS providing accurate position (±5m)'
                : 'GPS failed - using IMU dead reckoning (±20m)'
              }
            </div>
          </div>

          {/* <div className="bg-gradient-to-r from-yellow-50 to-yellow-100 p-3 rounded-lg border border-yellow-200">
            <div className="flex items-center gap-2 mb-2">
              <AlertTriangle className="w-4 h-4 text-yellow-600" />
              <span className="text-sm font-medium text-yellow-800">Storm Simulation</span>
            </div>
            <div className="text-xs text-yellow-700">
              Click on storm buttons in Space Weather panel
            </div>
          </div> */}
        </div>
      </div>

      {/* Vehicle Controls */}
      <div className="mb-6">
        <div className="text-sm font-medium text-gray-700 mb-3">Vehicle Controls</div>
        <div className="flex gap-2">
          <button
            onClick={onVehicleMoveToggle}
            className={`flex-1 py-3 rounded-lg font-medium flex items-center justify-center gap-2 ${vehicleMoving ? 'bg-gradient-to-r from-yellow-100 to-yellow-200 text-yellow-700' : 'bg-gradient-to-r from-primary to-primary-dark text-white shadow-md'}`}
          >
            {vehicleMoving ? (
              <>
                <Pause className="w-4 h-4" />
                Pause Journey
              </>
            ) : (
              <>
                <Play className="w-4 h-4" />
                Start Journey
              </>
            )}
          </button>

          <button
            onClick={onReset}
            className="p-3 rounded-lg bg-gradient-to-r from-gray-100 to-gray-200 text-gray-700 hover:from-gray-200 hover:to-gray-300 transition-colors shadow-sm"
            title="Reset simulation"
          >
            <RotateCcw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Route Points Status */}
      <div className="mb-6">
        <div className="text-sm font-medium text-gray-700 mb-3">Route Points</div>
        <div className="space-y-3">
          <div className="flex items-center justify-between bg-white p-3 rounded-lg border border-gray-200">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-blue-500"></div>
              <span className="text-sm">Start Point</span>
            </div>
            <div className="text-xs text-gray-500">
              {startPoint
                ? `${startPoint[0].toFixed(4)}, ${startPoint[1].toFixed(4)}`
                : <span className="text-gray-400">Not set</span>
              }
            </div>
          </div>

          <div className="flex items-center justify-between bg-white p-3 rounded-lg border border-gray-200">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-green-500"></div>
              <span className="text-sm">End Point</span>
            </div>
            <div className="text-xs text-gray-500">
              {endPoint
                ? `${endPoint[0].toFixed(4)}, ${endPoint[1].toFixed(4)}`
                : <span className="text-gray-400">Not set</span>
              }
            </div>
          </div>
        </div>
      </div>

      {/* Demo Routes */}
      <div>
        <div className="flex items-center gap-2 mb-3">
          <Zap className="w-4 h-4 text-orange-500" />
          <div className="text-sm font-medium text-gray-700">Quick Demo Routes</div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <button
            onClick={() => onUseDemoRoute('BLR_MUMBAI')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200"
          >
            Bengaluru → Mumbai
          </button>

          <button
            onClick={() => onUseDemoRoute('BLR_GOA')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200"
          >
            Bengaluru → Goa
          </button>

          <button
            onClick={() => onUseDemoRoute('BLR_MANGALURU')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200"
          >
            Bengaluru → Mangaluru
          </button>

          <button
            onClick={() => onUseDemoRoute('BLR_HYDERABAD')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200"
          >
            Bengaluru → Hyderabad
          </button>

          <button
            onClick={() => onUseDemoRoute('BLR_SHIVAMOGGA')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200"
          >
            Bengaluru → Shivamogga
          </button>

          <button
            onClick={() => onUseDemoRoute('BLR_KARWAR')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200"
          >
            Bengaluru → Karwar
          </button>

          <button
            onClick={() => onUseDemoRoute('BLR_CHIKKABALLAPUR')}
            className="py-2 px-3 text-xs bg-gradient-to-r from-gray-50 to-gray-100 hover:from-gray-100 hover:to-gray-200 rounded-lg transition-all border border-gray-200 col-span-2"
          >
            Bengaluru → Chikkaballapur
          </button>
        </div>
        <div className="text-xs text-gray-500 mt-2">
          Click "Set Points" to create custom routes
        </div>
      </div>
    </div>
  )
}

export default ControlPanel