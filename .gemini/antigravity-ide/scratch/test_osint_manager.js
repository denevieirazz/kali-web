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

async function testOsintManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO OSINT INTELLIGENCE HUB ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. EXECUTANDO VARREDURA OSINT (WHOIS) ===");
  const osintData = await post('/api/osint/scan', {
    domain: 'google.com',
    module: 'whois'
  }, auth.token);

  console.log("Status da Operação:", osintData.success);
  console.log("Comando Executado:", osintData.rawCommand);
  console.log("E-mails Encontrados:", osintData.data.emails.length);
  console.log("Subdomínios Encontrados:", osintData.data.subdomains.length);
  console.log("IPs Encontrados:", osintData.data.ips.length);
}

testOsintManager().catch(console.error);
