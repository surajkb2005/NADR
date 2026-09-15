//StellarRoute\frontend\src\utils\audioManager.js

class AudioManager {
  constructor() {
    this.audioElements = {};
    this.isMuted = false;
  }

  loadAudio(name, src) {
    if (!this.audioElements[name]) {
      const audio = new Audio(src);
      audio.loop = name.includes('emergency_siren.mp3') || name.includes('siren');
      audio.volume = 0.3;
      this.audioElements[name] = audio;
    }
    return this.audioElements[name];
  }

  play(name) {
    if (this.isMuted) return;
    const audio = this.audioElements[name];
    if (audio) {
      audio.currentTime = 0;
      audio.play().catch(e => console.log("Audio play failed:", e));
    }
  }

  stop(name) {
    const audio = this.audioElements[name];
    if (audio) {
      audio.pause();
      audio.currentTime = 0;
    }
  }

  stopAll() {
    Object.values(this.audioElements).forEach(audio => {
      audio.pause();
      audio.currentTime = 0;
    });
  }

  setVolume(name, volume) {
    const audio = this.audioElements[name];
    if (audio) {
      audio.volume = Math.max(0, Math.min(1, volume));
    }
  }

  muteAll() {
    this.isMuted = true;
    this.stopAll();
  }

  unmuteAll() {
    this.isMuted = false;
  }
}

export const audioManager = new AudioManager();