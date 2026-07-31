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

function post(path, data) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(data);
    const req = http.request({
      hostname: 'localhost',
      port: 8080,
      path,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
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

async function testProcessManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DA PROC API ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. TESTANDO LISTAGEM DE PROCESSOS (/api/processes) ===");
  const procData = await get('/api/processes', auth.token);
  console.log(`Processos encontrados: ${procData.count}`);
  if (procData.processes && procData.processes.length > 0) {
    console.log("Top Processo:", procData.processes[0]);
  }

  console.log("\n=== 3. TESTANDO RESUMO DE RECURSOS (/api/processes/stats/summary) ===");
  const statsData = await get('/api/processes/stats/summary', auth.token);
  console.log("Status de Recursos:", JSON.stringify(statsData.stats, null, 2));
}

testProcessManager().catch(console.error);
