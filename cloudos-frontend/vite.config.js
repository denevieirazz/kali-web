import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  define: {
    // Resolve o erro "process is not defined" no react-rnd/react-draggable
    'process.env': {}
  },
  server: {
    port: 5173
  }
});
