const http = require('http');

function request(method, path, data, token) {
  return new Promise((resolve, reject) => {
    const payload = data ? JSON.stringify(data) : '';
    const headers = {
      'Content-Type': 'application/json'
    };
    if (payload) headers['Content-Length'] = Buffer.byteLength(payload);
    if (token) headers['Authorization'] = 'Bearer ' + token;

    const req = http.request({
      hostname: 'localhost',
      port: 8080,
      path,
      method,
      headers
    }, res => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => resolve(JSON.parse(body)));
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function testHistoryManager() {
  console.log("=== 1. LOGIN PARA OBTER TOKEN ===");
  const auth = await request('POST', '/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha na autenticação");

  console.log("\n=== 2. SALVANDO HISTÓRICO DE DE SCAN TESTE ===");
  const saveRes = await request('POST', '/api/history', {
    tool: 'nmap',
    target: '127.0.0.1',
    status: 'success',
    result: { openPorts: [8080, 22], host: 'localhost' }
  }, auth.token);
  console.log("Resultado do salvamento:", saveRes);

  console.log("\n=== 3. LISTANDO HISTÓRICO (FILTRO POR TOOL=nmap) ===");
  const listRes = await request('GET', `/api/history?tool=nmap`, null, auth.token);
  console.log("Histórico encontrado:", listRes.history?.length, "itens");

  if (saveRes.id) {
    console.log("\n=== 4. BUSCANDO DETALHE DO REGISTRO ===");
    const detailRes = await request('GET', `/api/history/${saveRes.id}`, null, auth.token);
    console.log("Detalhes do scan salvo:", detailRes.data?.tool, detailRes.data?.target, detailRes.data?.result);

    console.log("\n=== 5. DELETANDO REGISTRO DE TESTE ===");
    const deleteRes = await request('DELETE', `/api/history/${saveRes.id}`, null, auth.token);
    console.log("Resultado da exclusão:", deleteRes);
  }
}

testHistoryManager().catch(console.error);
