import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import electron from 'vite-plugin-electron/simple';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const isElectron = process.env.ELECTRON === 'true';

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    ...(isElectron
      ? [
          electron({
            main: {
              entry: 'electron/main.ts',
            },
            preload: {
              input: path.join(__dirname, 'electron/preload.ts'),
            },
            renderer: {},
          }),
        ]
      : []),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5175,
    open: !isElectron,
    host: '0.0.0.0',
    proxy: !isElectron
      ? {
          '/api': {
            target: process.env.VITE_BACKEND_URL || 'http://192.168.1.91:8084',
            changeOrigin: true,
            secure: false,
          },
        }
      : undefined,
  },
  preview: {
    port: 5175,
    open: true,
    host: '0.0.0.0',
  },
});

