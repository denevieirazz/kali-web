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

async function testNetworkManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DA NETWORK API ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. TESTANDO STATUS DE SERVIÇOS TÁTICOS (/api/network/services) ===");
  const svcData = await get('/api/network/services', auth.token);
  console.log("Serviços:", JSON.stringify(svcData.services, null, 2));

  console.log("\n=== 3. TESTANDO INICIALIZAÇÃO DE SERVIÇO (apache2 start) ===");
  const startData = await post('/api/network/services/apache2/start', {}, auth.token);
  console.log("Resultado Start Apache2:", startData);

  console.log("\n=== 4. TESTANDO LISTAGEM DE PORTAS EM ESCUTA (/api/network/ports) ===");
  const portsData = await get('/api/network/ports', auth.token);
  console.log(`Portas Abertas Encontradas: ${portsData.ports ? portsData.ports.length : 0}`);
  if (portsData.ports && portsData.ports.length > 0) {
    console.log("Top Portas:", portsData.ports.slice(0, 5));
  }

  console.log("\n=== 5. PARANDO SERVIÇO DE TESTE (apache2 stop) ===");
  const stopData = await post('/api/network/services/apache2/stop', {}, auth.token);
  console.log("Resultado Stop Apache2:", stopData);
}

testNetworkManager().catch(console.error);
