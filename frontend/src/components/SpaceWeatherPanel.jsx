import React from 'react'
import { Sun, AlertTriangle, Satellite, Wind, Activity, RefreshCw } from 'lucide-react'
import { RISK_LEVELS, SCENARIO_CONFIG } from '../utils/constants'

const SpaceWeatherPanel = ({ 
  spaceWeather, 
  onRefresh, 
  onSimulate,
  simulationMode,
  loading = false 
}) => {
  if (!spaceWeather) {
    return (
      <div className="glass-card p-6 rounded-xl">
        <div className="flex items-center justify-center h-40">
          <div className="text-gray-500">Loading space weather data...</div>
        </div>
      </div>
    )
  }
  
  const { 
    kp_index, 
    risk_level, 
    estimated_gps_error_m, 
    alerts, 
    source,
    timestamp,
    solar_wind_speed
  } = spaceWeather
  
  const riskConfig = RISK_LEVELS[risk_level] || RISK_LEVELS.medium
  const kpPercentage = (kp_index / 9) * 100
  
  const formatTime = (timestamp) => {
    const date = new Date(timestamp)
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }
  
  return (
    <div className="glass-card p-6 rounded-xl">
      <div className="flex justify-between items-center mb-4">
        <div className="flex items-center gap-2">
          <Sun className="w-5 h-5 text-yellow-500" />
          <h2 className="text-xl font-bold text-gray-800">Space Weather Status</h2>
        </div>
        <div className="flex gap-2">
          <button
            onClick={onRefresh}
            disabled={loading}
            className="p-2 text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors disabled:opacity-50"
            title="Refresh data"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>
      
      {/* Kp Index Gauge */}
      <div className="mb-6">
        <div className="flex justify-between items-center mb-2">
          <div className="flex items-center gap-2">
            <Activity className="w-4 h-4 text-gray-600" />
            <span className="font-medium text-gray-700">Planetary K-index</span>
          </div>
          <div className="text-2xl font-bold">{kp_index.toFixed(1)}<span className="text-lg text-gray-500">/9</span></div>
        </div>
        
        <div className="relative h-4 bg-gray-200 rounded-full overflow-hidden">
          <div 
            className="absolute h-full rounded-full transition-all duration-500"
            style={{ 
              width: `${kpPercentage}%`,
              backgroundColor: riskConfig.color,
              backgroundImage: `linear-gradient(90deg, ${riskConfig.color}88, ${riskConfig.color})`
            }}
          ></div>
          <div className="absolute inset-0 flex">
            {[0, 3, 6, 9].map((mark) => (
              <div 
                key={mark}
                className="absolute h-4 w-px bg-white"
                style={{ left: `${(mark / 9) * 100}%` }}
              >
                <div className="absolute -bottom-5 text-xs text-gray-500 transform -translate-x-1/2">
                  {mark}
                </div>
              </div>
            ))}
          </div>
        </div>
        
        <div className="flex justify-between text-xs text-gray-500 mt-1">
          <span>Low Risk</span>
          <span>Moderate</span>
          <span>High Risk</span>
        </div>
      </div>
      
      {/* Risk Indicator */}
      <div className={`mb-6 p-4 rounded-lg border ${riskConfig.text} border-current/30 bg-gradient-to-r ${riskConfig.bg}/10 to-transparent`}>
        <div className="flex items-center gap-3">
          <AlertTriangle className={`w-6 h-6 ${riskConfig.text}`} />
          <div>
            <div className="font-bold text-lg">{riskConfig.label} RISK</div>
            <div className="text-sm opacity-80">GPS Error: {estimated_gps_error_m[0]}m - {estimated_gps_error_m[1]}m</div>
          </div>
        </div>
      </div>
      
      {/* Additional Metrics */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="bg-gray-50 p-3 rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <Wind className="w-4 h-4 text-gray-600" />
            <span className="text-sm font-medium text-gray-700">Solar Wind</span>
          </div>
          <div className="text-lg font-semibold">
            {solar_wind_speed ? `${solar_wind_speed} km/s` : 'N/A'}
          </div>
        </div>
        
        <div className="bg-gray-50 p-3 rounded-lg">
          <div className="flex items-center gap-2 mb-1">
            <Satellite className="w-4 h-4 text-gray-600" />
            <span className="text-sm font-medium text-gray-700">GPS Status</span>
          </div>
          <div className="text-lg font-semibold text-green-600">
            {estimated_gps_error_m[0] < 50 ? 'Good' : 'Degraded'}
          </div>
        </div>
      </div>
      
      {/* Alerts */}
      {alerts && alerts.length > 0 && (
        <div className="mb-6">
          <div className="text-sm font-medium text-gray-700 mb-2">Alerts</div>
          <div className="space-y-2">
            {alerts.map((alert, index) => (
              <div key={index} className="bg-yellow-50 border border-yellow-200 p-3 rounded-lg">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="w-4 h-4 text-yellow-600 flex-shrink-0 mt-0.5" />
                  <span className="text-sm text-yellow-800">{alert}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      
      {/* Simulation Controls */}
      <div className="border-t pt-4">
        <div className="text-sm font-medium text-gray-700 mb-3">Simulation Mode</div>
        <div className="flex gap-2">
          {Object.entries(SCENARIO_CONFIG).map(([key, config]) => (
            <button
              key={key}
              onClick={() => onSimulate(key)}
              className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-all ${config.color} border ${simulationMode && key === spaceWeather.source?.toLowerCase() ? 'border-gray-400 shadow-inner' : 'border-transparent'}`}
            >
              {config.label}
            </button>
          ))}
        </div>
        <div className="text-xs text-gray-500 mt-2">
          {simulationMode ? (
            <span className="text-orange-600">⚠️ Simulation Active: {source}</span>
          ) : (
            <span>Current source: {source}</span>
          )}
        </div>
      </div>
      
      {/* Timestamp */}
      <div className="text-xs text-gray-500 mt-4 pt-4 border-t">
        Last updated: {formatTime(timestamp)}
      </div>
    </div>
  )
}

export default SpaceWeatherPanel