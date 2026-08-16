import { extractRecoveryCodeFromText, normalizeReadableRecoveryCode } from './accountContract.js';

const MAX_RECOVERY_FILE_BYTES = 64 * 1024;

function assertRecoveryCode(code: string) {
  const normalized = normalizeReadableRecoveryCode(code);
  if (!normalized || normalized.length > 128) throw new Error('Código de recuperação inválido.');
  return normalized;
}

export async function copyRecoveryCode(code: string) {
  const normalized = assertRecoveryCode(code);
  await navigator.clipboard.writeText(normalized);
}

export async function saveRecoveryCodeAsText(code: string) {
  const normalized = assertRecoveryCode(code);
  const picker = (window as unknown as {
    showSaveFilePicker?: (options: unknown) => Promise<FileSystemFileHandle>;
  }).showSaveFilePicker;
  if (typeof picker !== 'function') {
    throw new Error('Este navegador não permite escolher com segurança onde salvar o arquivo. Use Copiar ou Imprimir.');
  }

  const handle = await picker({
    suggestedName: 'CloudOS-codigo-recuperacao.txt',
    types: [{
      description: 'Arquivo de texto',
      accept: { 'text/plain': ['.txt'] },
    }],
    excludeAcceptAllOption: true,
  });
  const writable = await (handle as unknown as { createWritable: () => Promise<{ write: (data: string) => Promise<void>; close: () => Promise<void>; abort?: () => Promise<void> }> }).createWritable();
  try {
    await writable.write(`${normalized}\n\nCloudOS — código de recuperação de uso único.\nGuarde este arquivo em um local seguro.\n`);
    await writable.close();
  } catch (error) {
    try { await writable.abort?.(); } catch {}
    throw error;
  }
}

export function printRecoveryCode(code: string) {
  const normalized = assertRecoveryCode(code);
  const frame = document.createElement('iframe');
  frame.title = 'Impressão do código de recuperação CloudOS';
  frame.style.position = 'fixed';
  frame.style.width = '1px';
  frame.style.height = '1px';
  frame.style.opacity = '0';
  frame.style.pointerEvents = 'none';
  frame.setAttribute('aria-hidden', 'true');
  document.body.appendChild(frame);

  const documentRef = frame.contentDocument;
  const windowRef = frame.contentWindow;
  if (!documentRef || !windowRef) {
    frame.remove();
    throw new Error('Não foi possível preparar a impressão.');
  }

  const cleanup = () => frame.remove();
  documentRef.open();
  documentRef.write('<!doctype html><html><head><meta charset="utf-8"><title>CloudOS — Recuperação</title></head><body></body></html>');
  documentRef.close();
  const heading = documentRef.createElement('h1');
  heading.textContent = 'Código de recuperação CloudOS';
  const codeElement = documentRef.createElement('pre');
  codeElement.textContent = normalized;
  codeElement.style.font = '700 18px/1.6 monospace';
  codeElement.style.letterSpacing = '0.08em';
  const note = documentRef.createElement('p');
  note.textContent = 'Este código é de uso único. Guarde a impressão em local seguro.';
  documentRef.body.append(heading, codeElement, note);
  windowRef.addEventListener('afterprint', cleanup, { once: true });
  window.setTimeout(cleanup, 60_000);
  windowRef.focus();
  windowRef.print();
}

export async function readRecoveryCodeTextFile(file: File) {
  if (file.size > MAX_RECOVERY_FILE_BYTES) throw new Error('O arquivo selecionado é grande demais para ser um código de recuperação.');
  const text = await file.text();
  const code = extractRecoveryCodeFromText(text);
  if (!code) throw new Error('Nenhum código de recuperação válido foi encontrado no arquivo.');
  return code;
}
