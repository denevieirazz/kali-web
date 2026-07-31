// 🚨 LINHA MÁGICA: Resolve o erro "process is not defined" do react-rnd no Vite
window.process = window.process || { env: { NODE_ENV: 'development' } };

import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'
import { runAutoFix } from './scripts/autoFix.js'

// Roda a limpeza automática de tokens e janelas corrompidas
runAutoFix();

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
