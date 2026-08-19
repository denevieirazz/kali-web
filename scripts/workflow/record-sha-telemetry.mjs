import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const SHA_REGEX = /^[0-9a-f]{40}$/i;

function getGit(args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8' }).trim();
  } catch (error) {
    try {
      return execFileSync('git.exe', args, { encoding: 'utf8' }).trim();
    } catch {
      return null;
    }
  }
}

function escapeTableCell(value) {
  if (value === null || value === undefined) return 'N/A';
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/\|/g, '\\|')
    .replace(/\r?\n/g, ' ')
    .replace(/`/g, '\\`');
}

const eventName = process.env.GITHUB_EVENT_NAME || 'local';
const ref = process.env.GITHUB_REF || getGit(['symbolic-ref', '-q', 'HEAD']) || 'local-ref';
const actualSha = getGit(['rev-parse', 'HEAD']);
const headSha = process.env.PR_HEAD_SHA || process.env.GITHUB_HEAD_SHA || (eventName === 'pull_request' ? process.env.PR_HEAD_SHA : actualSha);
const baseSha = process.env.PR_BASE_SHA || process.env.GITHUB_BASE_SHA || null;
const mergeSha = process.env.GITHUB_SHA || actualSha;
const expectedSha = process.env.EXPECTED_SHA || headSha || actualSha;

let errorCode = null;
let errorMessage = null;

if (!actualSha || !SHA_REGEX.test(actualSha)) {
  errorCode = 'INVALID_TESTED_SHA';
  errorMessage = `SHA testado inválido ou ausente: "${actualSha || 'NULL'}"`;
} else if (!expectedSha || !SHA_REGEX.test(expectedSha)) {
  errorCode = 'INVALID_EXPECTED_SHA';
  errorMessage = `SHA esperado inválido ou ausente: "${expectedSha || 'NULL'}"`;
} else if (actualSha.toLowerCase() !== expectedSha.toLowerCase()) {
  errorCode = 'SHA_MISMATCH';
  errorMessage = `Mismatch de SHA: esperado "${expectedSha}" mas executado "${actualSha}"`;
}

const isMatch = errorCode === null;

const telemetry = {
  timestamp: new Date().toISOString(),
  eventName,
  ref,
  testedSha: actualSha || 'N/A',
  headSha: headSha || 'N/A',
  baseSha: baseSha || 'N/A',
  mergeSha: mergeSha || 'N/A',
  expectedSha: expectedSha || 'N/A',
  match: isMatch,
  errorCode: errorCode || 'NONE',
  errorMessage: errorMessage || 'OK',
};

const outputDir = path.resolve(process.cwd(), process.env.TELEMETRY_OUTPUT_DIR || 'test-results');
fs.mkdirSync(outputDir, { recursive: true });
const outputFile = path.join(outputDir, 'sha-telemetry.json');
fs.writeFileSync(outputFile, `${JSON.stringify(telemetry, null, 2)}\n`, 'utf8');

const summaryLines = [
  '### 🛡️ SHA & Ref Verification Gate',
  '',
  '| Parâmetro | Valor |',
  '|---|---|',
  `| **Event Name** | \`${escapeTableCell(telemetry.eventName)}\` |`,
  `| **Ref** | \`${escapeTableCell(telemetry.ref)}\` |`,
  `| **Tested SHA (Checked Out)** | \`${escapeTableCell(telemetry.testedSha)}\` |`,
  `| **Head SHA (PR)** | \`${escapeTableCell(telemetry.headSha)}\` |`,
  `| **Base SHA** | \`${escapeTableCell(telemetry.baseSha)}\` |`,
  `| **Merge/Trigger SHA** | \`${escapeTableCell(telemetry.mergeSha)}\` |`,
  `| **Expected SHA** | \`${escapeTableCell(telemetry.expectedSha)}\` |`,
  `| **Status do Gate** | ${telemetry.match ? '✅ **PASS (Match Confirmado)**' : `❌ **FAIL (${telemetry.errorCode})**`} |`,
  '',
];

if (telemetry.errorMessage && !telemetry.match) {
  summaryLines.push(`> ⚠️ **Motivo da Reprovação:** ${escapeTableCell(telemetry.errorMessage)}`, '');
}

const summaryFile = process.env.GITHUB_STEP_SUMMARY;
if (summaryFile) {
  // Falha claramente se o arquivo foi especificado mas houver erro de escrita
  fs.appendFileSync(summaryFile, `${summaryLines.join('\n')}\n`, 'utf8');
}

console.log(`SHA_TELEMETRY_RECORDED=${outputFile}`);
console.log(`TESTED_SHA=${telemetry.testedSha} EXPECTED_SHA=${telemetry.expectedSha} MATCH=${telemetry.match} CODE=${telemetry.errorCode}`);

if (process.argv.includes('--gate') && !telemetry.match) {
  console.error(`::error::${telemetry.errorCode}: ${telemetry.errorMessage}`);
  process.exit(1);
}
