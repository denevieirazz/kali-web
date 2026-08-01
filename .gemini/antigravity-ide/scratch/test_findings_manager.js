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

async function testFindingsManager() {
  console.log("=== 1. AUTENTICANDO PARA TESTE DA FINDINGS & CUSTODY API ===");
  const auth = await post('/api/auth/login', { username: 'admin', password: 'admin123' });
  if (!auth.token) throw new Error("Falha ao obter token");

  console.log("\n=== 2. CRIANDO VULNERABILIDADE DE TESTE (/api/findings) ===");
  const createData = await post('/api/findings', {
    title: 'SQL Injection em /api/v1/auth',
    severity: 'Crítica',
    description: 'Parâmetro username vulnerável a bypass de autenticação por Union-Based SQLi.'
  }, auth.token);
  console.log("Finding Criado:", createData);

  const findingId = createData.finding.id;

  console.log("\n=== 3. LISTANDO VULNERABILIDADES (/api/findings) ===");
  const findingsList = await get('/api/findings', auth.token);
  console.log(`Total de falhas encontradas: ${findingsList.findings.length}`);

  console.log("\n=== 4. ANEXANDO EVIDÊNCIA BASE64 COM HASH SHA256 (/api/findings/:id/evidence) ===");
  const dummyBase64 = "data:text/plain;base64,U1FMIEluamVjdGlvbiBQcm9vZiBvZiBDb25jZXB0";
  const evidenceData = await post(`/api/findings/${findingId}/evidence`, {
    filename: 'sqli_poc_dump.txt',
    base64Data: dummyBase64
  }, auth.token);
  console.log("Evidência Registrada (Cadeia de Custódia):", evidenceData);

  console.log("\n=== 5. LISTANDO EVIDÊNCIAS REGISTRADAS (/api/findings/:id/evidence) ===");
  const evidenceList = await get(`/api/findings/${findingId}/evidence`, auth.token);
  console.log("Evidências no Cofre:", JSON.stringify(evidenceList.evidence, null, 2));
}

testFindingsManager().catch(console.error);
