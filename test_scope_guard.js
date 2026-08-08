const { validateTargetAgainstScope } = require('./cloudos-backend/services/scopeGuard');

const scopes = [
  { target: 'example.com', type: 'domain' },
  { target: '*.example.com', type: 'wildcard' },
  { target: '192.168.1.0/24', type: 'cidr' },
  { target: '10.0.0.5', type: 'ip' }
];

const tests = [
  { name: '1. Domain Match (example.com)', target: 'example.com', expected: true },
  { name: '2. Subdomain Wildcard (sub.example.com)', target: 'sub.example.com', expected: true },
  { name: '3. Evil Domain Suffix Attack (evil-example.com)', target: 'evil-example.com', expected: false },
  { name: '4. CIDR In-Range (192.168.1.15)', target: '192.168.1.15', expected: true },
  { name: '5. CIDR Out-of-Range (192.168.2.15)', target: '192.168.2.15', expected: false },
  { name: '6. Exact IP Match (10.0.0.5)', target: '10.0.0.5', expected: true },
  { name: '7. Unmatched IP (10.0.0.6)', target: '10.0.0.6', expected: false },
  { name: '8. Unrelated Domain (google.com)', target: 'google.com', expected: false }
];

let allPassed = true;
tests.forEach(t => {
  const result = validateTargetAgainstScope(t.target, scopes);
  const pass = result.allowed === t.expected;
  if (!pass) allPassed = false;
  console.log(`[${pass ? 'PASS' : 'FAIL'}] ${t.name} -> Result: ${result.allowed}, Expected: ${t.expected}`);
});

if (allPassed) {
  console.log('\n✅ TODOS OS TESTES DO SCOPE GUARD PASSARAM COM SUCESSO!');
} else {
  console.error('\n❌ HOUVE FALHA NO TESTE DO SCOPE GUARD!');
  process.exit(1);
}
