import { spawnSync } from 'node:child_process';

const commands = [
  ['npm', ['run', 'test:frontend'], 'frontend'],
  ['npm', ['test'], 'backend'],
  ['npm', ['run', 'test:e2e'], 'e2e'],
  ['npm', ['run', 'lint'], 'lint'],
];

for (const [command, args, label] of commands) {
  console.log(`HARDENING_REGRESSION_START ${label}`);
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    env: process.env,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`HARDENING_REGRESSION_FAILED ${label} exit=${result.status ?? 'signal'}`);
  }
  console.log(`HARDENING_REGRESSION_OK ${label}`);
}

console.log('HARDENING_REGRESSIONS_OK');
