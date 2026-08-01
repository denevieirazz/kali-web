const http = require('http');

function get(path, token) {
  return new Promise((resolve, reject) => {
    const headers = {};
    if (token) headers['Authorization'] = 'Bearer ' + token;
    const req = http.request({
      hostname: 'localhost',
      port: 8080,
      path,
      method: 'GET',
      headers
    }, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve(JSON.parse(body)));
    });
    req.on('error', reject);
    req.end();
  });
}

function post(path, data, token) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(data || {});
    const headers = {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload)
    };
    if (token) headers['Authorization'] = 'Bearer ' + token;

    const req = http.request({
      hostname: 'localhost',
      port: 8080,
      path,
      method: 'POST',
      headers
    }, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve(JSON.parse(body)));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function testMetasploitManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO METASPLOIT MSRPC ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. CHECANDO STATUS DO DAEMON METASPLOIT RPC (/api/metasploit/status) ===");
  const statusData = await get('/api/metasploit/status', auth.token);
  console.log("Status MSF RPC:", statusData);
}

testMetasploitManager().catch(console.error);
