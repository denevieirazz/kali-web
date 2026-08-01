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

async function testHashCrackerManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DO HASH CRACKER ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. TESTANDO QUEBRA DE HASH MD5 DA PALAVRA 'admin' ===");
  // Hash MD5 de 'admin' = 21232f297a57a5a743894a0e4a801fc3
  const crackData = await post('/api/hashcracker/crack', {
    hash: '21232f297a57a5a743894a0e4a801fc3',
    format: 'md5'
  }, auth.token);

  console.log("Status da Operação:", crackData.success);
  console.log("Senha Encontrada?:", crackData.cracked);
  console.log("Senha Decodificada:", crackData.password);
}

testHashCrackerManager().catch(console.error);
