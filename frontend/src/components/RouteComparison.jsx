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
    <div></div>
  )
}

export default RouteComparison