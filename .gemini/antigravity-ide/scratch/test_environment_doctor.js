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

async function testEnvironmentDoctor() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO ENVIRONMENT DOCTOR ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. EXECUTANDO DIAGNÓSTICO DO AMBIENTE KALI WSL (/api/environment/check) ===");
  const checkData = await get('/api/environment/check', auth.token);
  
  console.log("Summary:", checkData.summary);
  console.log("Sistema:", checkData.system);
  console.log("Disco:", checkData.disk);
  console.log("Memória:", checkData.memory);
  console.log(`Total de Ferramentas Verificadas: ${checkData.tools ? checkData.tools.length : 0}`);
  if (checkData.tools) {
    const installed = checkData.tools.filter(t => t.installed).map(t => t.name);
    const missing = checkData.tools.filter(t => !t.installed).map(t => t.name);
    console.log("Instaladas:", installed.slice(0, 5), `... (+${installed.length - 5})`);
    console.log("Faltando:", missing);
  }
}

testEnvironmentDoctor().catch(console.error);
