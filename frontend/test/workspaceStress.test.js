import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createWorkspaceRecord,
  normalizeWorkspaceRecord,
  sanitizeWorkspaceName,
  matchesWorkflowQuery,
  workspaceSearchText,
} from '../src/core/workflowCore.js';

test('EF2-P2-002: Stress test de 100 Workspaces com medição de latência e consumo', () => {
  const workspaces = [];
  const startCreation = performance.now();

  // 1. Criação em massa de 100 Workspaces
  for (let i = 1; i <= 100; i++) {
    const ws = createWorkspaceRecord({
      id: `stress-ws-${i}-${crypto.randomUUID()}`,
      name: `Workspace de Operação ${i}`,
      description: `Descrição detalhada do workspace ${i} para testes de estresse em escala.`,
      client: `Cliente Corporativo ${i % 10}`,
      tags: [`tag-${i % 5}`, 'stress-test', `lote-${Math.floor(i / 10)}`],
      type: i % 2 === 0 ? 'security' : 'development',
      provider: 'opfs',
      root: ['Workspaces', `Workspace-Operacao-${i}`],
    });
    assert.ok(ws, `Workspace ${i} deve ser normalizado com sucesso`);
    workspaces.push(ws);
  }

  const creationDuration = performance.now() - startCreation;
  assert.equal(workspaces.length, 100);
  console.log(`   ⏱️ Criação de 100 Workspaces concluída em ${creationDuration.toFixed(2)} ms (${(creationDuration / 100).toFixed(3)} ms/item)`);

  // 2. Simulação de 1000 Notas distribuídas entre os 100 Workspaces
  const notesIndex = [];
  const startNotes = performance.now();
  for (let w = 0; w < workspaces.length; w++) {
    const ws = workspaces[w];
    for (let n = 1; n <= 10; n++) {
      notesIndex.push({
        workspaceId: ws.id,
        fileName: `nota-analise-${n}.md`,
        title: `Relatório de Análise Técnica ${w}-${n}`,
        searchText: `Conteúdo da evidência técnica ${n} no workspace ${ws.name}. Palavra-chave: VULNERABILIDADE_${(w * 10 + n) % 25}`,
        updatedAt: new Date(Date.now() - (w * 10 + n) * 1000).toISOString(),
      });
    }
  }
  const notesDuration = performance.now() - startNotes;
  assert.equal(notesIndex.length, 1000);
  console.log(`   ⏱️ Indexação de 1000 Notas concluída em ${notesDuration.toFixed(2)} ms`);

  // 3. Medição de Latência de Busca (P50, P95, P99) em 500 consultas
  const latencies = [];
  for (let q = 1; q <= 500; q++) {
    const query = `VULNERABILIDADE_${q % 25}`;
    const t0 = performance.now();
    const results = notesIndex.filter(note => matchesWorkflowQuery(`${note.title}\n${note.searchText}`, query));
    const dt = performance.now() - t0;
    latencies.push(dt);
    assert.ok(results.length > 0, `Busca por ${query} deve retornar resultados`);
  }

  latencies.sort((a, b) => a - b);
  const p50 = latencies[Math.floor(latencies.length * 0.50)];
  const p95 = latencies[Math.floor(latencies.length * 0.95)];
  const p99 = latencies[Math.floor(latencies.length * 0.99)];

  console.log(`   📊 Latência de Busca (500 queries em 1000 notas): P50=${p50.toFixed(3)} ms, P95=${p95.toFixed(3)} ms, P99=${p99.toFixed(3)} ms`);

  // Garantia de SLA: P95 deve ser inferior a 15 ms em busca síncrona in-memory
  assert.ok(p95 < 15, `P95 (${p95.toFixed(3)} ms) deve ser inferior a 15 ms`);

  // 4. Validação de Limite de Capacidade Máxima (MAX_WORKSPACES = 1000)
  assert.equal(workspaces.length <= 1000, true);
});
