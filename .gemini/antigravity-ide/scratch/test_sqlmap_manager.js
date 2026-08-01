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

async function testSqlmapManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO SQLMAP SCANNER ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. EXECUTANDO VARREDURA SQLMAP BATCH (/api/sqlmap/scan) ===");
  const scanData = await post('/api/sqlmap/scan', {
    url: 'http://testphp.vulnweb.com/listproducts.php?cat=1'
  }, auth.token);

  console.log("Status Scan:", scanData.success);
  console.log("Vulnerável:", scanData.vulnerable);
  console.log("DBMS:", scanData.dbms);
  console.log("Databases Encontradas:", scanData.databases);
}

testSqlmapManager().catch(console.error);
