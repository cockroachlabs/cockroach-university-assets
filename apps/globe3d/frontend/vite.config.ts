import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    dedupe: ['react', 'react-dom', 'framer-motion', 'three'],
  },
  build: {
    outDir: '../dist',
    emptyOutDir: true,
  },
  server: {
    port: 3005,
    proxy: {
      '/api': 'http://localhost:9090',
      '/ws': {
        target: 'http://localhost:9090',
        ws: true,
      },
    },
  },
})
