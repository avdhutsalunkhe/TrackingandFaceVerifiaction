/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#fff4ed',
          100: '#ffe6d5',
          200: '#ffccaa',
          300: '#ffa673',
          400: '#ff7838',
          500: '#f95700', // Vibrant theme orange
          600: '#ea4e00',
          700: '#c23b00',
          800: '#9b2e00',
          900: '#7c2707',
          950: '#431102',
        },
        slate: {
          850: '#172033',
          900: '#111622',
          950: '#0b0f19',
        }
      },
      fontFamily: {
        sans: ['Inter', 'Segoe UI', '-apple-system', 'BlinkMacSystemFont', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Consolas', 'Courier New', 'monospace'],
      }
    },
  },
  plugins: [],
}

