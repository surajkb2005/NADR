export const DEMO_COORDINATES = {
  Bengaluru: [12.9716, 77.5946], // Bangalore
  Mumbai: [19.0760, 72.8777], // Mumbai
  GOA: [15.2993, 74.1240],
  KARWAR: [14.8000, 74.1333],
  SHIVAMOGGA: [13.9299, 75.5681],
  CHIKKABALLAPUR: [13.4350, 77.7315],
  MANGALURU: [12.9141, 74.8560],
  HYDERABAD: [17.3850, 78.4867],
}

export const SCENARIOS = {
  NORMAL: 'normal',
  MODERATE: 'moderate',
  SEVERE: 'severe'
}

export const SCENARIO_CONFIG = {
  normal: { label: 'Normal', kp: 2, color: 'bg-green-100' },
  moderate: { label: 'Moderate', kp: 5, color: 'bg-yellow-100' },
  severe: { label: 'Severe', kp: 8, color: 'bg-red-100' }
}

export const RISK_LEVELS = {
  low: { label: 'Low', color: '#4CAF50', bg: 'bg-risk-low', text: 'text-risk-low' },
  medium: { label: 'Medium', color: '#FFC107', bg: 'bg-risk-medium', text: 'text-risk-medium' },
  high: { label: 'High', color: '#F44336', bg: 'bg-risk-high', text: 'text-risk-high' }
}