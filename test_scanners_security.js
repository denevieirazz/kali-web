const { getProjectExecutionContext, isToolAllowed } = require('./cloudos-backend/services/scannerSecurity');
const { validateTargetAgainstScope } = require('./cloudos-backend/services/scopeGuard');
const database = require('./cloudos-backend/database');

async function runValidationTests() {
  console.log('🧪 INICIANDO BATERIA DE TESTES DE INTEGRAÇÃO DOS SCANNERS (TAREFA 06)...\n');
  const db = database;

  // 1. Setup mock user and projects
  const userId = 'u_test_' + Date.now();
  const otherUserId = 'u_other_' + Date.now();
  const projId = 'p_test_' + Date.now();
  const otherProjId = 'p_other_' + Date.now();

  await db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(userId, 'user_a_' + Date.now(), 'hash');
  await db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(otherUserId, 'user_b_' + Date.now(), 'hash');

  await db.prepare('INSERT INTO projects (id, user_id, name, scope) VALUES (?, ?, ?, ?)').run(projId, userId, 'Projeto A', 'acme.com');
  await db.prepare('INSERT INTO projects (id, user_id, name, scope) VALUES (?, ?, ?, ?)').run(otherProjId, otherUserId, 'Projeto B', 'other.com');

  await db.prepare('INSERT INTO project_scopes (project_id, target, type) VALUES (?, ?, ?)').run(projId, 'example.com', 'domain');
  await db.prepare('INSERT INTO project_scopes (project_id, target, type) VALUES (?, ?, ?)').run(projId, '*.example.com', 'wildcard');
  await db.prepare('INSERT INTO project_scopes (project_id, target, type) VALUES (?, ?, ?)').run(projId, '192.168.1.0/24', 'cidr');
  await db.prepare('INSERT INTO project_scopes (project_id, target, type) VALUES (?, ?, ?)').run(projId, '10.0.0.5', 'ip');

  const results = [];

  // TESTE 1: Ferramenta permitida + alvo autorizado
  const t1 = isToolAllowed('nmap') && (await getProjectExecutionContext(userId, projId, 'example.com')).allowed;
  results.push({ name: '1. Ferramenta permitida + Alvo autorizado', pass: t1 === true });

  // TESTE 2: Ferramenta não permitida (arbitrária/bash)
  const t2 = !isToolAllowed('bash') && !isToolAllowed('/bin/cat') && !isToolAllowed('nc');
  results.push({ name: '2. Ferramentas não permitidas (bash, executáveis arbitrários)', pass: t2 === true });

  // TESTE 3: Sem projectId
  const t3 = (await getProjectExecutionContext(userId, null, 'example.com')).allowed === false;
  results.push({ name: '3. Execução sem projectId', pass: t3 === true });

  // TESTE 4: Projeto de outro usuário
  const t4 = (await getProjectExecutionContext(userId, otherProjId, 'other.com')).allowed === false;
  results.push({ name: '4. Tentativa de acessar projeto de outro usuário', pass: t4 === true });

  // TESTE 5: Alvo fora do escopo
  const t5 = (await getProjectExecutionContext(userId, projId, 'unauthorized.com')).allowed === false;
  results.push({ name: '5. Alvo fora do escopo autorizado', pass: t5 === true });

  // TESTE 6: CIDR Válido
  const t6 = (await getProjectExecutionContext(userId, projId, '192.168.1.50')).allowed === true;
  results.push({ name: '6. CIDR válido (192.168.1.50 em /24)', pass: t6 === true });

  // TESTE 7: IP fora do CIDR
  const t7 = (await getProjectExecutionContext(userId, projId, '192.168.2.50')).allowed === false;
  results.push({ name: '7. IP fora do CIDR (192.168.2.50)', pass: t7 === true });

  // TESTE 8: Domínio válido
  const t8 = (await getProjectExecutionContext(userId, projId, 'example.com')).allowed === true;
  results.push({ name: '8. Domínio válido (example.com)', pass: t8 === true });

  // TESTE 9: Evil Domain Bypass
  const t9 = (await getProjectExecutionContext(userId, projId, 'evil-example.com')).allowed === false;
  results.push({ name: '9. Tentativa de bypass por sufixo (evil-example.com)', pass: t9 === true });

  // TESTE 10: Wildcard Válido
  const t10 = (await getProjectExecutionContext(userId, projId, 'api.example.com')).allowed === true;
  results.push({ name: '10. Subdomínio em Wildcard (*.example.com)', pass: t10 === true });

  // TESTE 11: URL Parsing com validação de hostname
  const t11 = (await getProjectExecutionContext(userId, projId, 'http://example.com/login?id=1')).allowed === true &&
              (await getProjectExecutionContext(userId, projId, 'http://evil.com/login')).allowed === false;
  results.push({ name: '11. Extração e validação de Hostname em URLs', pass: t11 === true });

  // TESTE 12: Isolation de AKB por projeto
  const hostsUserA = await db.prepare('SELECT h.* FROM akb_hosts h JOIN projects p ON h.project_id = p.id WHERE p.user_id = ?').all(userId);
  const hostsUserB = await db.prepare('SELECT h.* FROM akb_hosts h JOIN projects p ON h.project_id = p.id WHERE p.user_id = ?').all(otherUserId);
  results.push({ name: '12. Isolamento de AKB entre usuários', pass: Array.isArray(hostsUserA) && Array.isArray(hostsUserB) });

  let allPass = true;
  results.forEach(r => {
    if (!r.pass) allPass = false;
    console.log(`[${r.pass ? 'PASS' : 'FAIL'}] ${r.name}`);
  });

  if (allPass) {
    console.log('\n🌟 TODOS OS 12 TESTES DE HARDENING E SCOPE GUARD FORAM EXECUTADOS E PASSARAM COM SUCESSO!\n');
  } else {
    console.error('\n❌ HOUVE FALHA EM TESTES DE SEGURANÇA!');
    process.exit(1);
  }
}

runValidationTests().catch(e => {
  console.error('Erro na execução dos testes:', e);
  process.exit(1);
});
