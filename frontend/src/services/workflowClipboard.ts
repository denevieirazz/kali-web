import {
  MAX_CLIPBOARD_ITEMS,
  clipboardTextPolicy,
  normalizeClipboardMetadata,
  type ClipboardMetadata,
} from '../core/workflowCore.js';
import { getDirAt, readFile, writeTextFile } from '../apps/CloudOSFiles/opfsFileService';

const CLIPBOARD_KEY = 'cloudos.workflow.clipboard.v3';
const CLIPBOARD_PATH = ['.cloudos-workflow', 'Clipboard'];

export type { ClipboardMetadata };

function safeLoad() {
  if (typeof localStorage === 'undefined') return [] as ClipboardMetadata[];
  try {
    return normalizeClipboardMetadata(JSON.parse(localStorage.getItem(CLIPBOARD_KEY) || '[]'));
  } catch {
    return [] as ClipboardMetadata[];
  }
}

function save(entries: ClipboardMetadata[]) {
  if (typeof localStorage !== 'undefined') localStorage.setItem(CLIPBOARD_KEY, JSON.stringify(normalizeClipboardMetadata(entries)));
  if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('cloudos:clipboard-changed'));
}

async function ensureClipboardPath() {
  await getDirAt(CLIPBOARD_PATH, true);
}

async function removePayload(fileName: string) {
  try {
    const dir = await getDirAt(CLIPBOARD_PATH, true);
    await dir.removeEntry(fileName);
  } catch {
    // Metadata cleanup remains valid even if the payload was already gone.
  }
}

export function listClipboardEntries() {
  return safeLoad();
}

export async function addClipboardText(text: string, source = 'CloudOS') {
  const policy = clipboardTextPolicy(text);
  if (!policy.allowed) return { stored: false as const, reason: policy.reason };

  const existing = safeLoad();
  const duplicate = existing.find(item => item.preview === text.slice(0, 180) && item.bytes === policy.bytes && item.source === source);
  if (duplicate) {
    const next = [{ ...duplicate, createdAt: new Date().toISOString() }, ...existing.filter(item => item.id !== duplicate.id)];
    save(next);
    return { stored: true as const, entry: next[0], reason: 'deduplicated' as const };
  }

  await ensureClipboardPath();
  const id = crypto.randomUUID();
  const fileName = `${id}.txt`;
  await writeTextFile(CLIPBOARD_PATH, fileName, text);
  const entry: ClipboardMetadata = {
    id,
    source: String(source || 'CloudOS').slice(0, 40),
    createdAt: new Date().toISOString(),
    bytes: policy.bytes,
    preview: text.replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, 180),
    favorite: false,
    fileName,
  };

  const next = [entry, ...existing];
  const overflow = next.slice(MAX_CLIPBOARD_ITEMS);
  save(next.slice(0, MAX_CLIPBOARD_ITEMS));
  await Promise.all(overflow.map(item => removePayload(item.fileName)));
  return { stored: true as const, entry, reason: 'stored' as const };
}

export async function readClipboardText(entryOrId: ClipboardMetadata | string) {
  const entry = typeof entryOrId === 'string' ? safeLoad().find(item => item.id === entryOrId) : entryOrId;
  if (!entry) throw new Error('Entrada do clipboard não encontrada.');
  const file = await readFile(CLIPBOARD_PATH, entry.fileName, false);
  if (file.size !== entry.bytes || file.size > 5 * 1024 * 1024) throw new Error('Conteúdo do clipboard falhou na validação de tamanho.');
  const text = await file.text();
  const policy = clipboardTextPolicy(text);
  if (!policy.allowed) {
    await removeClipboardEntry(entry.id);
    throw new Error('A entrada foi removida porque passou a ser classificada como sensível ou inválida.');
  }
  return text;
}

export function toggleClipboardFavorite(id: string) {
  const next = safeLoad().map(item => item.id === id ? { ...item, favorite: !item.favorite } : item);
  save(next);
  return next.find(item => item.id === id) || null;
}

export async function removeClipboardEntry(id: string) {
  const entries = safeLoad();
  const target = entries.find(item => item.id === id);
  save(entries.filter(item => item.id !== id));
  if (target) await removePayload(target.fileName);
}

export async function clearClipboardHistory({ keepFavorites = false } = {}) {
  const entries = safeLoad();
  const kept = keepFavorites ? entries.filter(item => item.favorite) : [];
  const removed = keepFavorites ? entries.filter(item => !item.favorite) : entries;
  save(kept);
  await Promise.all(removed.map(item => removePayload(item.fileName)));
}

function sourceFromTarget(target: EventTarget | null) {
  const element = target instanceof Element ? target : document.activeElement;
  if (!(element instanceof Element)) return 'CloudOS';
  if (element.closest('.terminal-pane, .terminal-workspace')) return 'Terminal';
  if (element.closest('.cf-root')) return 'Files';
  if (element.closest('.workflow-notes')) return 'Workspace Notes';
  if (element.closest('.workflow-workspace')) return 'Workspace';
  return 'CloudOS';
}

function selectedText(target: EventTarget | null) {
  const element = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement ? target : null;
  if (element) {
    if (element instanceof HTMLInputElement && element.type === 'password') return '';
    const start = element.selectionStart ?? 0;
    const end = element.selectionEnd ?? start;
    return start === end ? '' : element.value.slice(start, end);
  }
  return window.getSelection()?.toString() || '';
}

export function installGlobalClipboardCapture() {
  if (typeof document === 'undefined') return () => undefined;
  const onCopy = (event: ClipboardEvent) => {
    const target = event.target;
    const text = event.clipboardData?.getData('text/plain') || selectedText(target);
    if (!text) return;
    void addClipboardText(text, sourceFromTarget(target)).catch(() => undefined);
  };
  document.addEventListener('copy', onCopy, true);
  return () => document.removeEventListener('copy', onCopy, true);
}

function insertIntoActiveElement(text: string) {
  const element = document.activeElement;
  if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
    if (element instanceof HTMLInputElement && element.type === 'password') return false;
    const start = element.selectionStart ?? element.value.length;
    const end = element.selectionEnd ?? start;
    element.setRangeText(text, start, end, 'end');
    element.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }
  if (element instanceof HTMLElement && element.isContentEditable) {
    const selection = window.getSelection();
    if (!selection?.rangeCount) return false;
    const range = selection.getRangeAt(0);
    range.deleteContents();
    const node = document.createTextNode(text);
    range.insertNode(node);
    range.setStartAfter(node);
    range.collapse(true);
    selection.removeAllRanges();
    selection.addRange(range);
    element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
    return true;
  }
  return false;
}

export async function copyClipboardEntryToSystem(entry: ClipboardMetadata) {
  const text = await readClipboardText(entry);
  if (!navigator.clipboard?.writeText) throw new Error('Clipboard do sistema não está disponível nesta sessão.');
  await navigator.clipboard.writeText(text);
  return text;
}

export async function pasteClipboardEntry(entry: ClipboardMetadata) {
  const text = await readClipboardText(entry);
  const inserted = typeof document !== 'undefined' ? insertIntoActiveElement(text) : false;
  if (!inserted && navigator.clipboard?.writeText) await navigator.clipboard.writeText(text);
  return { inserted, text };
}
