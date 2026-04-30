export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        crdb: {
          green: '#6933FF',
          dark: '#0A0E1A',
          darker: '#060910',
          card: '#111827',
          border: '#1F2937',
          accent: '#818CF8',
          success: '#34D399',
          danger: '#F87171',
          warning: '#FBBF24',
          muted: '#6B7280',
        },
        'region-us': '#60A5FA',
        'region-eu': '#34D399',
        'region-ap': '#FBBF24',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
    },
  },
  plugins: [],
}
