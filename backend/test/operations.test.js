import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createOperation,
  getActiveOperation,
  getOperation,
  resetOperationsForTests,
  runProcessOperation
} from '../src/operations/operationManager.js';

async function waitForCompletion(id, timeout = 5000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const operation = getOperation(id);
    if (['completed', 'failed', 'cancelled'].includes(operation.status)) return operation;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('A operação de teste não terminou.');
}

test('operações: acompanha saída e conclui processo real', async () => {
  resetOperationsForTests();
  const operation = createOperation('test', 'fixture');
  runProcessOperation(operation, process.execPath, ['-e', 'console.log("50% concluído")']);
  const finished = await waitForCompletion(operation.id);
  assert.equal(finished.status, 'completed');
  assert.equal(finished.progress, 100);
  assert.ok(finished.output.some((line) => line.includes('50%')));
});

test('operações: expõe mutação ativa para impedir concorrência', () => {
  resetOperationsForTests();
  const operation = createOperation('wsl_install', 'Ubuntu');
  assert.equal(getActiveOperation(['wsl_install'])?.id, operation.id);
  assert.equal(getActiveOperation(['wsl_update']), null);
});

test('operações: preserva falha e código de saída', async () => {
  resetOperationsForTests();
  const operation = createOperation('test_failure', 'fixture');
  runProcessOperation(operation, process.execPath, ['-e', 'console.error("falha controlada"); process.exit(7)']);
  const finished = await waitForCompletion(operation.id);
  assert.equal(finished.status, 'failed');
  assert.equal(finished.exitCode, 7);
  assert.equal(finished.errorCode, 'EXIT_7');
});
