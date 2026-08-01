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

async function testReportsGenerator() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO REPORTS GENERATOR ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. GERANDO RELATÓRIO HTML EXECUTA (/api/reports/generate?format=html) ===");
  const htmlData = await get('/api/reports/generate?format=html&client=Banco%20Acme%20S.A.', auth.token);
  console.log("Status HTML:", htmlData.success);
  console.log("Tamanho do HTML Gerado:", htmlData.report ? htmlData.report.length : 0, "caracteres");

  console.log("\n=== 3. GERANDO RELATÓRIO MARKDOWN (.MD) (/api/reports/generate?format=markdown) ===");
  const mdData = await get('/api/reports/generate?format=markdown&client=Banco%20Acme%20S.A.', auth.token);
  console.log("Status Markdown:", mdData.success);
  console.log("Relatório Markdown Gerado:\n");
  console.log(mdData.report);
}

testReportsGenerator().catch(console.error);
