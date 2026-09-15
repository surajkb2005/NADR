export const chaosEffects = {
  getRandomError() {
    const errors = [
      "GPS SIGNAL LOST: Solar interference detected",
      "SYSTEM ERROR: Satellite network compromised",
      "WARNING: Geomagnetic storm in progress",
      "CRITICAL: IMU calibration failing",
      "ALERT: Radiation levels exceeding safety limits"
    ];
    return errors[Math.floor(Math.random() * errors.length)];
  },

  getRandomGlitchStyle() {
    const glitches = [
      { transform: 'translate(2px, 1px)' },
      { transform: 'translate(-1px, -2px)' },
      { transform: 'translate(3px, 0px)' },
      { transform: 'translate(0px, 3px)' },
      { transform: 'translate(-2px, 2px)' }
    ];
    return glitches[Math.floor(Math.random() * glitches.length)];
  },

  getRandomColorInvert() {
    return Math.random() > 0.5 ? 'invert(100%)' : 'invert(0%)';
  },

  getScreenShakeIntensity(level) {
    const intensities = [
      '0px',
      '2px',
      '5px',
      '10px',
      '15px'
    ];
    return intensities[level] || intensities[2];
  }
};