/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'risk-low': '#4CAF50',
        'risk-medium': '#FFC107',
        'risk-high': '#F44336',
        'primary': '#2563eb',
        'secondary': '#7c3aed',
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'float': 'float 3s ease-in-out infinite',
        'shake': 'shake 0.5s infinite',
        'shake-hard': 'shake-hard 0.3s infinite',
        'glitch': 'glitch 0.3s infinite',
        'pulse-red': 'pulse-red 1s infinite',
        'flash': 'flash 0.8s infinite',
        'spin': 'spin 2s linear infinite',
        'wobble': 'wobble 0.5s infinite',
        'pixelate': 'pixelate 1s infinite',
        'invert': 'invert-colors 2s infinite',
      },
      keyframes: {
        float: {
          "0%, 100%": { transform: "translateY(0px)" },
          "50%": { transform: "translateY(-10px)" }
        },
        shake: {
          "0%, 100%": { transform: "translateX(0)" },
          "10%, 30%, 50%, 70%, 90%": { transform: "translateX(-5px)" },
          "20%, 40%, 60%, 80%": { transform: "translateX(5px)" }
        },
        'shake-hard': {
          "0%, 100%": { transform: "translate(0, 0) rotate(0deg)" },
          "10%": { transform: "translate(-10px, 5px) rotate(-1deg)" },
          "20%": { transform: "translate(8px, -3px) rotate(1deg)" },
          "30%": { transform: "translate(-7px, 4px) rotate(-0.5deg)" },
          "40%": { transform: "translate(6px, -2px) rotate(0.5deg)" },
          "50%": { transform: "translate(-5px, 3px) rotate(-0.3deg)" },
          "60%": { transform: "translate(4px, -1px) rotate(0.3deg)" },
          "70%": { transform: "translate(-3px, 2px) rotate(-0.1deg)" },
          "80%": { transform: "translate(2px, 0) rotate(0.1deg)" },
          "90%": { transform: "translate(-1px, 1px) rotate(0deg)" }
        },
        glitch: {
          "0%": { transform: "translate(0)", clipPath: "inset(0 0 0 0)" },
          "20%": { transform: "translate(-2px, 2px)", clipPath: "inset(20% 0 60% 0)" },
          "40%": { transform: "translate(-2px, -2px)", clipPath: "inset(60% 0 20% 0)" },
          "60%": { transform: "translate(2px, 2px)", clipPath: "inset(10% 0 80% 0)" },
          "80%": { transform: "translate(2px, -2px)", clipPath: "inset(80% 0 10% 0)" },
          "100%": { transform: "translate(0)", clipPath: "inset(0 0 0 0)" }
        },
        'pulse-red': {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.7" }
        },
        flash: {
          "0%, 50%, 100%": { opacity: "1" },
          "25%, 75%": { opacity: "0.3" }
        },
        spin: {
          from: { transform: "rotate(0deg)" },
          to: { transform: "rotate(360deg)" }
        },
        wobble: {
          "0%, 100%": { transform: "rotate(0deg)" },
          "25%": { transform: "rotate(5deg)" },
          "75%": { transform: "rotate(-5deg)" }
        },
        pixelate: {
          "0%, 100%": { filter: "none" },
          "50%": { filter: "contrast(2) blur(0.5px)" }
        },
        'invert-colors': {
          "0%, 100%": { filter: "invert(0)" },
          "50%": { filter: "invert(1)" }
        }
      }
    },
  },
  plugins: [],
}