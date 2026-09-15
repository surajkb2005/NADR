import React from 'react'
import { Navigation, Shield, Clock, MapPin, AlertTriangle, TrendingUp } from 'lucide-react'
import { RISK_LEVELS } from '../utils/constants'

const RouteComparison = ({ routes, currentMode, onSelectRoute }) => {
  // Determine if we have a valid route set to compare
  const hasRoutes = routes && (routes.normal || routes.safe)
  
  if (!hasRoutes) {
    return (
      <div className="glass-card p-6 rounded-xl">
        <div className="flex items-center justify-center h-40">
          <div className="text-gray-500">Calculate a route to see comparison</div>
        </div>
      </div>
    )
  }
  
  // LOGIC CHANGE: If a drifted route exists (Storm Active), use it for the "Normal" comparison
  // This shows the user the "Real World" bad outcome of using normal GPS
  const isDrifting = !!routes.drifted
  const normalRoute = isDrifting ? routes.drifted : routes.normal
  const safeRoute = routes.safe
  
  const formatTime = (seconds) => {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
  }
  
  const formatDistance = (meters) => {
    if (meters < 1000) {
      return `${Math.round(meters)}m`
    }
    return `${(meters / 1000).toFixed(1)}km`
  }
  
  const calculateDifference = (normalVal, safeVal, type) => {
    if (normalVal === undefined || safeVal === undefined) return 'N/A'
    if (normalVal === 0) return safeVal === 0 ? '0%' : '+100%'

    if (type === 'distance' || type === 'time') {
      const diff = safeVal - normalVal
      const percent = (diff / normalVal) * 100
      // If Safe is 'better' (less distance/time), show green
      const isBetter = percent < 0
      const sign = percent > 0 ? '+' : ''
      return (
        <span className={isBetter ? 'text-green-600' : 'text-orange-600'}>
          {sign}{percent.toFixed(0)}%
        </span>
      )
    }
    
    if (type === 'risk') {
      const diff = safeVal - normalVal // e.g. 20 - 80 = -60
      const percent = (diff / normalVal) * 100
      // If Safe is 'better' (less risk), show green
      const isBetter = percent < 0
      const sign = percent > 0 ? '+' : ''
      return (
        <span className={isBetter ? 'text-green-600' : 'text-red-600'}>
          {sign}{percent.toFixed(0)}%
        </span>
      )
    }
    
    return 'N/A'
  }
  
  return (
    <div className="glass-card p-6 rounded-xl">
      <div className="flex items-center gap-2 mb-6">
        <TrendingUp className="w-5 h-5 text-primary" />
        <h2 className="text-xl font-bold text-gray-800">Route Comparison</h2>
      </div>
      
      {/* Route Selection Tabs */}
      <div className="flex mb-6 bg-gray-100 p-1 rounded-lg">
        <button
          onClick={() => onSelectRoute('normal')}
          className={`flex-1 py-2 rounded-md text-center font-medium transition-all ${currentMode === 'normal' ? 'bg-white shadow-sm text-primary' : 'text-gray-600 hover:text-gray-900'}`}
        >
          <div className="flex items-center justify-center gap-2">
            <Navigation className="w-4 h-4" />
            Normal
          </div>
        </button>
        <button
          onClick={() => onSelectRoute('safe')}
          className={`flex-1 py-2 rounded-md text-center font-medium transition-all ${currentMode === 'safe' ? 'bg-white shadow-sm text-green-600' : 'text-gray-600 hover:text-gray-900'}`}
        >
          <div className="flex items-center justify-center gap-2">
            <Shield className="w-4 h-4" />
            Storm-Safe
          </div>
        </button>
      </div>
      
      {/* Comparison Table */}
      <div className="overflow-hidden rounded-lg border border-gray-200">
        <table className="w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="py-3 px-4 text-left text-xs font-bold text-gray-500 uppercase tracking-wider">Metric</th>
              <th className="py-3 px-4 text-left text-xs font-bold text-gray-500 uppercase tracking-wider">
                {isDrifting ? (
                  <span className="text-red-600 flex items-center gap-1">
                    Normal <span className="text-[10px] bg-red-100 px-1 rounded">DRIFTING</span>
                  </span>
                ) : (
                  "Normal"
                )}
              </th>
              <th className="py-3 px-4 text-left text-xs font-bold text-gray-500 uppercase tracking-wider text-green-700">
                Safe
              </th>
              <th className="py-3 px-4 text-left text-xs font-bold text-gray-500 uppercase tracking-wider">Diff</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {/* Distance */}
            <tr className="hover:bg-gray-50">
              <td className="py-3 px-4">
                <div className="flex items-center gap-2">
                  <MapPin className="w-4 h-4 text-gray-500" />
                  <span className="text-sm font-medium text-gray-700">Distance</span>
                </div>
              </td>
              <td className="py-3 px-4">
                <span className={`font-medium ${isDrifting ? 'text-red-600' : 'text-gray-900'}`}>
                  {formatDistance(normalRoute?.distance_m || 0)}
                </span>
              </td>
              <td className="py-3 px-4">
                <span className="font-medium text-green-700">{formatDistance(safeRoute?.distance_m || 0)}</span>
              </td>
              <td className="py-3 px-4 text-sm font-medium">
                {calculateDifference(normalRoute?.distance_m, safeRoute?.distance_m, 'distance')}
              </td>
            </tr>
            
            {/* Time */}
            <tr className="hover:bg-gray-50">
              <td className="py-3 px-4">
                <div className="flex items-center gap-2">
                  <Clock className="w-4 h-4 text-gray-500" />
                  <span className="text-sm font-medium text-gray-700">Est. Time</span>
                </div>
              </td>
              <td className="py-3 px-4">
                <span className="font-medium">{formatTime(normalRoute?.estimated_time_s || 0)}</span>
              </td>
              <td className="py-3 px-4">
                <span className="font-medium text-green-700">{formatTime(safeRoute?.estimated_time_s || 0)}</span>
              </td>
              <td className="py-3 px-4 text-sm font-medium">
                {calculateDifference(normalRoute?.estimated_time_s, safeRoute?.estimated_time_s, 'time')}
              </td>
            </tr>
            
            {/* Risk Score */}
            <tr className="hover:bg-gray-50">
              <td className="py-3 px-4">
                <div className="flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 text-gray-500" />
                  <span className="text-sm font-medium text-gray-700">Risk Score</span>
                </div>
              </td>
              <td className="py-3 px-4">
                <div className="flex items-center gap-2">
                  <div className={`w-3 h-3 rounded-full ${RISK_LEVELS[normalRoute?.max_risk_zone]?.bg || 'bg-gray-300'}`}></div>
                  <span className="font-medium">{normalRoute?.total_risk_score?.toFixed(0) || 0}/100</span>
                </div>
              </td>
              <td className="py-3 px-4">
                <div className="flex items-center gap-2">
                  <div className={`w-3 h-3 rounded-full ${RISK_LEVELS[safeRoute?.max_risk_zone]?.bg || 'bg-gray-300'}`}></div>
                  <span className="font-medium text-green-700">{safeRoute?.total_risk_score?.toFixed(0) || 0}/100</span>
                </div>
              </td>
              <td className="py-3 px-4 text-sm font-medium">
                {calculateDifference(normalRoute?.total_risk_score, safeRoute?.total_risk_score, 'risk')}
              </td>
            </tr>
            
            {/* Max Risk Zone */}
            <tr className="hover:bg-gray-50">
              <td className="py-3 px-4">
                <div className="flex items-center gap-2">
                  <Shield className="w-4 h-4 text-gray-500" />
                  <span className="text-sm font-medium text-gray-700">Risk Zone</span>
                </div>
              </td>
              <td className="py-3 px-4">
                <span className={`px-2 py-1 rounded-full text-xs font-medium ${RISK_LEVELS[normalRoute?.max_risk_zone]?.text} ${RISK_LEVELS[normalRoute?.max_risk_zone]?.bg}/20`}>
                  {normalRoute?.max_risk_zone?.toUpperCase() || 'N/A'}
                </span>
              </td>
              <td className="py-3 px-4">
                <span className={`px-2 py-1 rounded-full text-xs font-medium ${RISK_LEVELS[safeRoute?.max_risk_zone]?.text} ${RISK_LEVELS[safeRoute?.max_risk_zone]?.bg}/20`}>
                  {safeRoute?.max_risk_zone?.toUpperCase() || 'N/A'}
                </span>
              </td>
              <td className="py-3 px-4">
                <span className={`text-sm font-medium ${
                  normalRoute?.max_risk_zone === safeRoute?.max_risk_zone ? 'text-gray-400' : 'text-green-600'
                }`}>
                  {normalRoute?.max_risk_zone === safeRoute?.max_risk_zone ? '—' : 'Improved'}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      
      {/* Dynamic Summary */}
      <div className={`mt-6 p-4 rounded-lg border ${isDrifting ? 'bg-red-50 border-red-100' : 'bg-blue-50 border-blue-100'}`}>
        <div className={`text-sm font-bold mb-2 ${isDrifting ? 'text-red-800' : 'text-blue-800'}`}>
          {isDrifting ? '⚠️ WARNING: GPS DEGRADATION DETECTED' : 'System Status: Normal'}
        </div>
        <div className={`text-sm ${isDrifting ? 'text-red-700' : 'text-blue-700'}`}>
          {isDrifting ? (
            <>
              Normal GPS route is drifting by significant margins. 
              Switching to <b>Storm-Safe</b> mode reduces risk score by 
              <b> {calculateDifference(normalRoute?.total_risk_score, safeRoute?.total_risk_score, 'risk')}</b>.
            </>
          ) : (
            <>
              Conditions are stable. Normal route is optimal. 
              Safe route adds <b>{calculateDifference(normalRoute?.distance_m, safeRoute?.distance_m, 'distance')}</b> distance.
            </>
          )}
        </div>
      </div>
      
      {/* Action Buttons */}
      <div className="flex gap-3 mt-6">
        <button
          onClick={() => onSelectRoute('normal')}
          className={`flex-1 py-3 rounded-lg font-medium transition-colors ${
            currentMode === 'normal' 
              ? 'bg-blue-600 text-white shadow-md' 
              : 'bg-white border border-gray-200 text-gray-700 hover:bg-gray-50'
          }`}
        >
          Use Normal Route
        </button>
        <button
          onClick={() => onSelectRoute('safe')}
          className={`flex-1 py-3 rounded-lg font-medium transition-colors ${
            currentMode === 'safe' 
              ? 'bg-green-600 text-white shadow-md' 
              : 'bg-white border border-gray-200 text-gray-700 hover:bg-gray-50'
          }`}
        >
          Use Safe Route
        </button>
      </div>
    </div>
  )
}

export default RouteComparison