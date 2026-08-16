import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createTerminalTransport,
  sanitizeTerminalError,
  WSL_CORE_MODE,
  WSL_CORE_PROTECTION,
} from '../src/apps/CloudOSTerminal/terminalSessionTransport.js';

class FakeSocket {
  constructor() { this.readyState = 0; this.sent = []; this.listeners = new Map(); this.closeCalls = 0; }
  addEventListener(type, handler) { const set = this.listeners.get(type) || new Set(); set.add(handler); this.listeners.set(type, set); }
  removeEventListener(type, handler) { this.listeners.get(type)?.delete(handler); }
  send(value) { this.sent.push(JSON.parse(String(value))); }
  close() { this.closeCalls += 1; this.readyState = 3; }
  emit(type, detail = {}) { if (type === 'open') this.readyState = 1; if (type === 'close') this.readyState = 3; for (const handler of [...(this.listeners.get(type) || [])]) handler({ type, ...detail }); }
  message(value) { this.emit('message', { data: JSON.stringify(value) }); }
  listenerCount() { return [...this.listeners.values()].reduce((sum, set) => sum + set.size, 0); }
}

function make(overrides = {}) {
  const socket = new FakeSocket(); const statuses = []; const output = []; const notices = []; const exits = [];
  const transport = createTerminalTransport({ socket, profile: 'wsl', distribution: 'kali-linux', initialCols: 80, initialRows: 24,
    onStatus: status => statuses.push(status), onOutput: data => output.push(data), onNotice: notice => notices.push(notice), onExit: exit => exits.push(exit), ...overrides });
  return { socket, transport, statuses, output, notices, exits };
}
function ready(fixture) { fixture.socket.emit('open'); fixture.socket.message({ type: 'backend', mode: WSL_CORE_MODE, protocol: 2, protection: WSL_CORE_PROTECTION }); }

test('só marca connected depois do backend WSL Core v2 pronto', () => {
  const f = make(); f.socket.emit('open'); assert.equal(f.statuses.at(-1).state, 'connecting');
  assert.deepEqual(f.socket.sent[0], { type: 'start', profile: 'wsl', distribution: 'kali-linux', cols: 80, rows: 24 });
  f.socket.message({ type: 'backend', mode: WSL_CORE_MODE, protocol: 2, protection: WSL_CORE_PROTECTION });
  assert.equal(f.statuses.at(-1).state, 'connected'); assert.equal(f.statuses.at(-1).mode, WSL_CORE_MODE);
});

test('input é byte-preservado e Ctrl+C vira signal interrupt sem comando implícito', () => {
  const f = make(); ready(f); f.socket.sent.length = 0;
  assert.equal(f.transport.input("printf 'sem-enter'"), true); assert.deepEqual(f.socket.sent.shift(), { type: 'input', data: "printf 'sem-enter'" });
  assert.equal(f.transport.input('\x03'), true); assert.deepEqual(f.socket.sent.shift(), { type: 'signal', signal: 'interrupt' });
});

test('resize antes de ready guarda só a dimensão mais recente e envia após backend', () => {
  const f = make(); f.transport.resize(90, 26); f.transport.resize(120, 38); f.socket.emit('open'); f.transport.resize(132, 41);
  assert.equal(f.socket.sent.filter(item => item.type === 'resize').length, 0);
  f.socket.message({ type: 'backend', mode: WSL_CORE_MODE, protocol: 2, protection: WSL_CORE_PROTECTION });
  assert.deepEqual(f.socket.sent.filter(item => item.type === 'resize'), [{ type: 'resize', cols: 132, rows: 41 }]);
});

test('output é escrito sem transformação e exit fecha lifecycle', () => {
  const f = make(); ready(f); f.socket.message({ type: 'output', data: '\u001b[32mLinux\u001b[0m\r\n' });
  assert.equal(f.output[0], '\u001b[32mLinux\u001b[0m\r\n'); f.socket.message({ type: 'exit', exitCode: 130, signal: 'interrupt' });
  assert.equal(f.statuses.at(-1).state, 'closed'); assert.deepEqual(f.exits[0], { exitCode: 130, signal: 'interrupt' });
});

test('fallback legado é explicitamente visível', () => {
  const f = make(); f.socket.emit('open'); f.socket.message({ type: 'warning', data: 'WSL Core indisponível; usando fallback legado explícito.' });
  f.socket.message({ type: 'backend', mode: 'legacy-pty' }); assert.equal(f.statuses.at(-1).state, 'legacy-fallback'); assert.equal(f.statuses.at(-1).mode, 'legacy-pty'); assert.equal(f.notices.length, 1);
});

test('falha antes do backend permanece fail-closed e nunca inventa fallback', () => {
  const f = make(); f.socket.emit('open'); f.socket.message({ type: 'error', data: 'WSL Core falhou (CHANNEL_READINESS_TIMEOUT).' });
  assert.equal(f.statuses.at(-1).state, 'failed'); f.socket.emit('close'); assert.equal(f.statuses.at(-1).state, 'failed');
});

test('erro exibido remove endpoint, PID e material com aparência de segredo', () => {
  const clean = sanitizeTerminalError(`falhou 127.0.0.1:48123 pid=999 token=${'A'.repeat(64)}`);
  assert.doesNotMatch(clean, /48123|999|A{20}/); assert.match(clean, /agente local/); assert.match(clean, /redigido|detalhe interno/);
});

test('close envia close uma vez e dispose remove handlers sem duplicação', () => {
  const f = make(); ready(f); f.socket.sent.length = 0; f.transport.close(); assert.equal(f.statuses.at(-1).state, 'closing');
  assert.deepEqual(f.socket.sent, [{ type: 'close' }]); f.transport.close(); assert.equal(f.socket.sent.length, 1); f.transport.dispose(); f.transport.dispose(); assert.equal(f.socket.listenerCount(), 0);
});

test('desmontagem encerra backend e eventos tardios não acionam callbacks', () => {
  const f = make(); ready(f); f.socket.sent.length = 0; f.transport.dispose(); assert.deepEqual(f.socket.sent, [{ type: 'close' }]);
  const count = f.output.length; f.socket.message({ type: 'output', data: 'late' }); assert.equal(f.output.length, count); assert.equal(f.socket.listenerCount(), 0);
});

test('remount não conserva listeners da sessão anterior', () => {
  const first = make(); ready(first); first.transport.dispose(); const second = make(); ready(second);
  second.socket.message({ type: 'output', data: 'one' }); first.socket.message({ type: 'output', data: 'stale' }); assert.deepEqual(second.output, ['one']); assert.deepEqual(first.output, []);
});
