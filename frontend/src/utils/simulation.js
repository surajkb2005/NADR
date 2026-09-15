// Enhanced GPS Failure Simulation Utilities
export class GPSSimulator {
  constructor(startPosition) {
    this.position = startPosition
    this.gpsActive = true
    this.driftPath = []
    this.lastKnownPosition = startPosition
    this.driftMagnitude = 0
    this.driftDirection = Math.random() * Math.PI * 2 // Random initial direction
    this.driftStep = 0
  }
  
  simulateGPSFailure(riskLevel, severity = 'medium') {
    this.gpsActive = false
    this.driftMagnitude = this.getDriftFromRisk(riskLevel, severity)
    this.driftPath = [this.position]
    this.driftStep = 0
    return this.position
  }
  
  getDriftFromRisk(riskLevel, severity) {
    // Base drift based on risk level
    let baseDrift
    switch(riskLevel) {
      case 'low': baseDrift = 0.00005; // ~5.5m per step
      break;
      case 'medium': baseDrift = 0.0002; // ~22m per step
      break;
      case 'high': baseDrift = 0.0005; // ~55m per step
      break;
      default: baseDrift = 0.0001
    }
    
    // Adjust based on storm severity
    switch(severity) {
      case 'low': return baseDrift * 0.5;
      case 'medium': return baseDrift;
      case 'high': return baseDrift * 2.0;
      default: return baseDrift;
    }
  }
  
  updatePosition() {
    if (this.gpsActive) {
      return this.position
    }
    
    this.driftStep++
    
    // Simulate realistic drift pattern (random walk with bias)
    const angleVariation = (Math.random() - 0.5) * Math.PI / 4 // ±22.5 degrees variation
    this.driftDirection += angleVariation
    
    // Add some systematic drift
    const systematicDrift = 0.1 * Math.sin(this.driftStep / 10)
    this.driftDirection += systematicDrift
    
    // Calculate drift vector
    const driftX = Math.cos(this.driftDirection) * this.driftMagnitude
    const driftY = Math.sin(this.driftDirection) * this.driftMagnitude
    
    const [lat, lon] = this.position
    const newLat = lat + driftY
    const newLon = lon + driftX
    
    this.position = [newLat, newLon]
    this.driftPath.push(this.position)
    
    return this.position
  }
  
  restoreGPS() {
    this.gpsActive = true
    this.position = this.lastKnownPosition
    return this.position
  }
  
  reset() {
    this.gpsActive = true
    this.driftPath = []
    this.driftMagnitude = 0
    this.driftStep = 0
  }
  
  getCurrentDriftDistance() {
    if (this.driftPath.length < 2) return 0
    const start = this.driftPath[0]
    const end = this.driftPath[this.driftPath.length - 1]
    const latDiff = (end[0] - start[0]) * 111000 // meters per degree
    const lonDiff = (end[1] - start[1]) * 111000 * Math.cos(start[0] * Math.PI / 180)
    return Math.sqrt(latDiff * latDiff + lonDiff * lonDiff)
  }
}

// Enhanced Vehicle Animation
export class VehicleAnimator {
  constructor(route, speed = 30) { // meters per second
    this.route = route
    this.speed = speed
    this.currentIndex = 0
    this.progress = 0
    this.isMoving = false
    this.lastUpdate = Date.now()
    this.totalDistance = this.calculateTotalDistance()
  }
  
  calculateTotalDistance() {
    if (this.route.length < 2) return 0
    
    let total = 0
    for (let i = 1; i < this.route.length; i++) {
      total += this.calculateSegmentDistance(this.route[i-1], this.route[i])
    }
    return total
  }
  
  calculateSegmentDistance(point1, point2) {
    const [lat1, lon1] = point1
    const [lat2, lon2] = point2
    const R = 6371000 // Earth radius in meters
    
    const lat1Rad = lat1 * Math.PI / 180
    const lat2Rad = lat2 * Math.PI / 180
    const deltaLat = (lat2 - lat1) * Math.PI / 180
    const deltaLon = (lon2 - lon1) * Math.PI / 180
    
    const a = Math.sin(deltaLat/2) * Math.sin(deltaLat/2) +
              Math.cos(lat1Rad) * Math.cos(lat2Rad) *
              Math.sin(deltaLon/2) * Math.sin(deltaLon/2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    
    return R * c
  }
  
  start() {
    this.isMoving = true
    this.lastUpdate = Date.now()
  }
  
  pause() {
    this.isMoving = false
  }
  
  reset() {
    this.currentIndex = 0
    this.progress = 0
    this.isMoving = false
    this.lastUpdate = Date.now()
  }
  
  getCurrentPosition() {
    if (this.route.length < 2) return this.route[0] || [0, 0]
    
    if (this.currentIndex >= this.route.length - 1) {
      return this.route[this.route.length - 1]
    }
    
    const start = this.route[this.currentIndex]
    const end = this.route[this.currentIndex + 1]
    
    const lat = start[0] + (end[0] - start[0]) * this.progress
    const lon = start[1] + (end[1] - start[1]) * this.progress
    
    return [lat, lon]
  }
  
  update() {
    if (!this.isMoving || this.route.length < 2) return this.getCurrentPosition()
    
    const now = Date.now()
    const deltaTime = (now - this.lastUpdate) / 1000 // seconds
    this.lastUpdate = now
    
    // Calculate distance traveled in this frame
    const distanceTraveled = this.speed * deltaTime
    
    // Convert to progress along current segment
    if (this.currentIndex < this.route.length - 1) {
      const start = this.route[this.currentIndex]
      const end = this.route[this.currentIndex + 1]
      const segmentLength = this.calculateSegmentDistance(start, end)
      
      const progressIncrement = distanceTraveled / segmentLength
      this.progress += progressIncrement
      
      if (this.progress >= 1) {
        this.currentIndex++
        this.progress = 0
        
        if (this.currentIndex >= this.route.length - 1) {
          this.isMoving = false // Reached destination
        }
      }
    }
    
    return this.getCurrentPosition()
  }
  
  getProgressPercentage() {
    if (this.totalDistance === 0) return 0
    
    let distanceCovered = 0
    for (let i = 0; i < this.currentIndex; i++) {
      distanceCovered += this.calculateSegmentDistance(this.route[i], this.route[i+1])
    }
    
    if (this.currentIndex < this.route.length - 1) {
      const start = this.route[this.currentIndex]
      const end = this.route[this.currentIndex + 1]
      const currentSegmentDistance = this.calculateSegmentDistance(start, end)
      distanceCovered += currentSegmentDistance * this.progress
    }
    
    return (distanceCovered / this.totalDistance) * 100
  }
}

// IMU Navigation System
export class IMUNavigator {
  constructor(startPosition, route = null) {
    this.position = startPosition
    this.route = route || [startPosition]
    this.currentIndex = 0
    this.progress = 0
    this.speed = 15 // Conservative speed for IMU navigation
    this.accuracy = 0.8 // IMU navigation accuracy (0-1)
    this.correctionInterval = 5 // Apply correction every 5 seconds
    this.lastCorrection = Date.now()
    this.errorAccumulation = 0
  }
  
  update() {
    if (this.route.length < 2) return this.position
    
    const now = Date.now()
    const deltaTime = (now - this.lastUpdate || now) / 1000
    this.lastUpdate = now
    
    // Apply IMU error accumulation
    this.errorAccumulation += deltaTime * 0.001 // Error accumulates over time
    
    // Calculate movement with error
    if (this.currentIndex < this.route.length - 1) {
      const start = this.route[this.currentIndex]
      const end = this.route[this.currentIndex + 1]
      
      const distance = this.calculateDistance(start, end)
      const progressIncrement = (this.speed * deltaTime) / distance
      
      this.progress += progressIncrement * this.accuracy
      
      // Add random IMU error
      const randomError = (Math.random() - 0.5) * this.errorAccumulation * 0.0001
      this.progress += randomError
      
      if (this.progress >= 1) {
        this.currentIndex++
        this.progress = 0
        
        if (this.currentIndex >= this.route.length - 1) {
          this.progress = 1
        }
      }
    }
    
    // Calculate position with possible correction
    let position = this.calculatePosition()
    
    // Apply periodic correction (simulating sensor fusion)
    if ((now - this.lastCorrection) / 1000 >= this.correctionInterval) {
      position = this.applyCorrection(position)
      this.lastCorrection = now
    }
    
    this.position = position
    return position
  }
  
  calculatePosition() {
    if (this.currentIndex >= this.route.length - 1) {
      return this.route[this.route.length - 1]
    }
    
    const start = this.route[this.currentIndex]
    const end = this.route[this.currentIndex + 1]
    
    const lat = start[0] + (end[0] - start[0]) * this.progress
    const lon = start[1] + (end[1] - start[1]) * this.progress
    
    return [lat, lon]
  }
  
  applyCorrection(position) {
    // Simulate occasional position correction (e.g., from landmarks, WiFi)
    if (Math.random() > 0.3) return position
    
    const [lat, lon] = position
    const correction = 0.00001 * (Math.random() - 0.5) // Small correction
    
    return [lat + correction, lon + correction]
  }
  
  calculateDistance(point1, point2) {
    const [lat1, lon1] = point1
    const [lat2, lon2] = point2
    const latDiff = (lat2 - lat1) * 111000
    const lonDiff = (lon2 - lon1) * 111000 * Math.cos(lat1 * Math.PI / 180)
    return Math.sqrt(latDiff * latDiff + lonDiff * lonDiff)
  }
  
  reset() {
    this.currentIndex = 0
    this.progress = 0
    this.errorAccumulation = 0
    this.lastCorrection = Date.now()
  }
}