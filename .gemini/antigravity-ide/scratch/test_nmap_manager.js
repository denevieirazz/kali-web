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

async function testNmapManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO NMAP SCANNER ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. EXECUTANDO VARREDURA NMAP RÁPIDA (/api/nmap/scan) ===");
  const scanData = await post('/api/nmap/scan', {
    target: 'scanme.nmap.org',
    profile: 'fast'
  }, auth.token);

  console.log("Status Scan:", scanData.success);
  console.log("Comando Executado:", scanData.rawCommand);
  console.log("Hosts Encontrados:", JSON.stringify(scanData.hosts, null, 2));
}

testNmapManager().catch(console.error);
