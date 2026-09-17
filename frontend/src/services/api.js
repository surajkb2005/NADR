// frontend/src/services/api.js
import axios from 'axios'

const API_BASE_URL = '/api';

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10000,
  withCredentials: true,
});

export const stellarRouteAPI = {
  // Space Weather
  getCurrentSpaceWeather: (lat, lon) =>
    api.get('/space-weather/current', { params: { latitude: lat, longitude: lon } }),

  simulateStorm: (scenario, lat, lon) =>
    api.get('/space-weather/simulate', {
      params: { scenario, latitude: lat, longitude: lon }
    }),

  stopSimulation: () => api.get('/space-weather/stop-simulation'),

  getStormTimeline: (scenario) =>
    api.get('/space-weather/timeline', { params: { scenario } }),

  // Heatmap
  getHeatmap: (bbox, resolution = 0.05) =>
    api.post('/heatmap', { bbox, resolution }),

  // Routing
  calculateRoute: (start, end, mode = 'normal') =>
    api.post('/route', { start, end, mode }),

  // Health
  checkHealth: () => api.get('/health'),

  // --- NEW AUTHENTICATION ENDPOINTS ---
  requestOtp: (email) => { // Use the 'api' instance
    return api.post('/auth/request-otp', { email });
  },

  verifyOtp: (email, otp) => { // Use the 'api' instance
    return api.post('/auth/verify-otp', { email, otp });
  },

  logout: () => { // Use the 'api' instance
    return api.post('/auth/logout');
  },

  checkAuthStatus: () => api.get('/auth/status'),
};

// Helper functions (Unchanged)
export const calculateBoundingBox = (center, radiusKm = 5) => {
  const [lat, lon] = center
  const latDelta = radiusKm / 111.32 // 1 degree latitude ≈ 111.32 km
  const lonDelta = radiusKm / (111.32 * Math.cos(lat * Math.PI / 180))

  return [
    lon - lonDelta, // minLon
    lat - latDelta, // minLat
    lon + lonDelta, // maxLon
    lat + latDelta // maxLat
  ]
};

export default api;