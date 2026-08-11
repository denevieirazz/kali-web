import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

// Configurações
app.use(cors());
app.use(express.json());

// Banco de Dados Simulado (Em produção, você pode usar um arquivo JSON ou MongoDB)
let cloudRegistry = {};

// ============================================
// API ENDPOINTS (LiveMode)
// ============================================

// Sincronização de Registro e Configurações
app.post('/api/v1/sync', (req, res) => {
  const { username, settings, timestamp } = req.body;
  if (!username) return res.status(400).json({ error: 'Username required' });

  console.log(`[CloudSync] Recebendo dados de: ${username} (${new Date(timestamp).toLocaleTimeString()})`);
  
  cloudRegistry[username] = {
    ...settings,
    lastSync: timestamp
  };

  res.json({ status: 'success', message: 'Dados salvos na nuvem ObsidianOS' });
});

// Autenticação / Login
app.post('/api/v1/auth/login', (req, res) => {
  const { username, password } = req.body;
  
  // LOGICA DE DEMONSTRAÇÃO: Aceita qualquer usuário, e se a senha for vazia, loga direto.
  console.log(`[Auth] Tentativa de login: ${username}`);

  res.json({
    token: `obsidian_token_${Date.now()}`,
    user: {
      username: username,
      displayName: username.charAt(0).toUpperCase() + username.slice(1),
      avatar: `https://api.dicebear.com/7.x/avataaars/svg?seed=${username}`,
      isAdmin: true
    }
  });
});

// ============================================
// SERVINDO O FRONTEND (SISTEMA OPERACIONAL)
// ============================================

// Servir os arquivos estáticos da pasta 'dist'
app.use(express.static(path.join(__dirname, 'dist')));

// Lógica de SPA: Se não for uma rota de API ou arquivo estático, serve o index.html
app.use((req, res) => {
  res.sendFile(path.join(__dirname, 'dist', 'index.html'));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log('============================================');
  console.log('   ObsidianOS LIVE - Servidor Unificado');
  console.log(`   Rodando em: http://localhost:${PORT}`);
  console.log('============================================');
});
