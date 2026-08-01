const express = require('express');
const router = express.Router();
const net = require('net');
const msgpack = require('msgpack-lite');
const { exec } = require('child_process');
const { authenticateToken } = require('../middleware/auth');

router.use(authenticateToken);

// Configurações do Daemon MSF RPC
const MSF_HOST = '127.0.0.1';
const MSF_PORT = 55553;
const MSF_USER = 'cloudos';
const MSF_PASS = 'cloudos';

// Cliente MSF RPC
class MsfRpcClient {
  constructor() {
    this.token = null;
    this.connecting = null;
  }

  async connect() {
    if (this.token) return this.token;
    if (this.connecting) return this.connecting;

    this.connecting = new Promise(async (resolve, reject) => {
      try {
        const tokenData = await this.call('auth.login', MSF_USER, MSF_PASS);
        this.token = tokenData?.token || tokenData;
        this.connecting = null;
        resolve(this.token);
      } catch (err) {
        this.connecting = null;
        reject(err);
      }
    });
    return this.connecting;
  }

  call(method, ...args) {
    return new Promise((resolve, reject) => {
      const socket = net.connect(MSF_PORT, MSF_HOST);
      const decodeStream = msgpack.createDecodeStream();
      let settled = false;

      const cleanup = () => {
        socket.destroy();
        decodeStream.removeAllListeners();
      };

      socket.pipe(decodeStream);

      decodeStream.on('data', (data) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(data);
      });

      socket.on('error', (err) => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(err);
      });

      setTimeout(() => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(new Error('Timeout na comunicação com MSF RPC'));
      }, 10000);

      const payload = msgpack.encode([method, ...args]);
      socket.write(payload);
    });
  }
}

const client = new MsfRpcClient();

/**
 * GET /api/metasploit/status
 */
router.get('/status', async (req, res) => {
  try {
    await client.connect();
    res.json({ running: true });
  } catch (err) {
    res.json({ running: false, error: err.message });
  }
});

/**
 * POST /api/metasploit/start
 * Inicia o daemon msfrpcd no WSL2
 */
router.post('/start', async (req, res) => {
  try {
    try {
      await client.connect();
      return res.json({ success: true, message: 'MSF RPC já está rodando' });
    } catch (e) {
      const cmd = `wsl -d kali-linux -u cloudos -- bash -c "msfrpcd -U ${MSF_USER} -P ${MSF_PASS} -p ${MSF_PORT} -a ${MSF_HOST} -f"`;
      exec(cmd, { timeout: 5000 }, () => {});

      setTimeout(async () => {
        try {
          await client.connect();
          res.json({ success: true, message: 'MSF RPC iniciado com sucesso' });
        } catch (err2) {
          res.status(500).json({ 
            success: false, 
            error: 'Falha ao iniciar MSF RPC. Verifique se o metasploit-framework está instalado.' 
          });
        }
      }, 5000);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/metasploit/modules/:type
 */
router.get('/modules/:type', async (req, res) => {
  try {
    const { type } = req.params;
    await client.connect();
    const mods = await client.call('module.' + type, client.token);
    res.json({ modules: mods?.modules || mods || [] });
  } catch (err) {
    res.status(500).json({ error: 'Falha ao listar módulos', details: err.message });
  }
});

/**
 * GET /api/metasploit/options/:type/:name
 */
router.get('/options/:type/*?', async (req, res) => {
  try {
    const type = req.params.type;
    const name = req.params[0] || req.params.name;
    await client.connect();
    const opts = await client.call('module.options', client.token, type, name);
    res.json({ options: opts });
  } catch (err) {
    res.status(500).json({ error: 'Falha ao obter opções', details: err.message });
  }
});

/**
 * POST /api/metasploit/execute
 */
router.post('/execute', async (req, res) => {
  try {
    const { type, name, options } = req.body;
    await client.connect();
    const result = await client.call('module.execute', client.token, type, name, options);
    res.json({ result });
  } catch (err) {
    res.status(500).json({ error: 'Falha ao executar módulo', details: err.message });
  }
});

/**
 * GET /api/metasploit/sessions
 */
router.get('/sessions', async (req, res) => {
  try {
    await client.connect();
    const sessions = await client.call('session.list', client.token);
    const arr = sessions ? Object.keys(sessions).map(id => ({ id, ...sessions[id] })) : [];
    res.json({ sessions: arr });
  } catch (err) {
    res.status(500).json({ error: 'Falha ao listar sessões', details: err.message });
  }
});

module.exports = router;
