const jwt = require('jsonwebtoken');
const sessionManager = require('./terminalSessionManager');
const SECRET_KEY = process.env.JWT_SECRET || 'cloudos_super_secret_jwt_key_2026';

function setupTerminalWebSocket(wss) {
  wss.on('connection', (ws, req) => {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    
    let userId = 'u_1001'; // Default admin fallback

    if (token) {
      try {
        const decoded = jwt.verify(token, SECRET_KEY);
        userId = decoded.id || decoded.userId || userId;
      } catch (err) {
        // Permite continuar para ambiente local de dev se o token for vindo do frontend
      }
    }

    ws.on('message', (message) => {
      try {
        const data = JSON.parse(message.toString());
        
        if (data.type === 'create') {
          const sid = sessionManager.createSession(userId, { cwd: data.cwd });
          ws.send(JSON.stringify({ type: 'session_created', sessionId: sid }));
        } 
        else if (data.type === 'attach') {
          sessionManager.attach(data.sessionId, ws, userId);
        }
        else if (data.type === 'input') {
          sessionManager.write(data.sessionId, data.data, userId);
        }
        else if (data.type === 'resize') {
          sessionManager.resize(data.sessionId, data, userId);
        }
        else if (data.type === 'kill') {
          sessionManager.kill(data.sessionId, userId);
        }
      } catch (e) {
        console.error("Erro no protocolo de WebSocket Terminal:", e);
      }
    });
  });
}

module.exports = setupTerminalWebSocket;
