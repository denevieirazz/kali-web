const http = require('http');

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

async function test() {
  console.log("=== 1. TESTANDO AUTENTICAÇÃO ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  console.log("Login Admin:", auth.token ? "✅ Sucesso (Token gerado)" : "❌ Falha");

  console.log("\n=== 2. TESTANDO DIAGNÓSTICO DO SISTEMA (ENVIRONMENT DOCTOR) ===");
  const doctor = await get('/api/v3/doctor', auth.token);
  console.log("Resultado do Doctor:", JSON.stringify(doctor, null, 2));

  console.log("\n=== 3. TESTANDO SISTEMA DE ARQUIVOS (CLOUD FS) ===");
  const files = await get('/api/files?path=', auth.token);
  console.log("Items na Raiz do Sistema:", files.items ? `✅ ${files.items.length} itens encontrados` : "❌ Falha ao listar");

  console.log("\n=== 4. TESTANDO JOBS QUEUE & DEPLOYMENT PIPELINE ===");
  const jobs = await get('/api/v3/jobs', auth.token);
  console.log("Fila de Jobs:", Array.isArray(jobs) ? `✅ ${jobs.length} jobs registrados` : "❌ Falha nos jobs");
}

test().catch(console.error);
