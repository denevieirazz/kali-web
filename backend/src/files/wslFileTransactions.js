import { createOperation, runManagedOperation } from '../operations/operationManager.js';
import { wslFilesService } from './wslFilesService.js';

const CHUNK_SIZE = 256 * 1024;
const MAX_TREE_ENTRIES = 10000;

function clonePath(value) {
  return Array.isArray(value) ? value.map(String) : [];
}

async function getEntry(path) {
  if (!path.length) throw Object.assign(new Error('A raiz não pode ser copiada.'), { code: 'FILES_PATH_INVALID' });
  const parent = path.slice(0, -1);
  const name = path.at(-1);
  const listing = await wslFilesService.request('fs.list', { path: parent }, 15000);
  const entry = listing?.entries?.find(candidate => candidate?.name === name);
  if (!entry) throw Object.assign(new Error('Arquivo ou pasta não encontrado.'), { code: 'FILES_NOT_FOUND' });
  if (entry.symlink || entry.kind === 'symlink') throw Object.assign(new Error('Symlinks não podem ser copiados neste escopo.'), { code: 'FILES_SYMLINK_DENIED' });
  if (!['file', 'directory'].includes(entry.kind)) throw Object.assign(new Error('Tipo de entrada não suportado.'), { code: 'FILES_TYPE_DENIED' });
  return entry;
}

async function buildPlan(source, destination, signal) {
  const root = await getEntry(source);
  const directories = [];
  const files = [];
  let totalBytes = 0;
  let count = 0;

  async function walk(sourcePath, destinationPath, entry) {
    if (signal.aborted) throw Object.assign(new Error('cancelled'), { code: 'OPERATION_CANCELLED' });
    count += 1;
    if (count > MAX_TREE_ENTRIES) throw Object.assign(new Error('A árvore excede o limite transacional.'), { code: 'FILES_TREE_LIMIT' });

    if (entry.kind === 'file') {
      const size = Number.isFinite(Number(entry.size)) ? Math.max(0, Number(entry.size)) : 0;
      files.push({ source: clonePath(sourcePath), destination: clonePath(destinationPath), size, mode: Number(entry.mode) || 0o600 });
      totalBytes += size;
      return;
    }

    directories.push({ destination: clonePath(destinationPath), mode: Number(entry.mode) || 0o700 });
    const listing = await wslFilesService.request('fs.list', { path: sourcePath }, 15000);
    for (const child of listing?.entries || []) {
      if (child?.symlink || child?.kind === 'symlink') throw Object.assign(new Error('A árvore contém symlink e foi recusada.'), { code: 'FILES_SYMLINK_DENIED' });
      if (!['file', 'directory'].includes(child?.kind)) throw Object.assign(new Error('A árvore contém tipo não suportado.'), { code: 'FILES_TYPE_DENIED' });
      await walk([...sourcePath, child.name], [...destinationPath, child.name], child);
    }
  }

  await walk(source, destination, root);
  return { root, directories, files, totalBytes, entries: count };
}

async function rollbackDestination(destination) {
  try {
    const trashed = await wslFilesService.request('fs.trash', { path: destination }, 10000);
    if (trashed?.id) await wslFilesService.request('fs.trash.delete', { id: trashed.id }, 15000);
  } catch {}
}

export function startWslCopyTransaction(source, destination) {
  const operation = createOperation('files.wsl.copy', {
    source: clonePath(source),
    destination: clonePath(destination),
    sourceType: 'wsl',
    destinationType: 'wsl',
  }, 'Preparando cópia Linux transacional...');

  const runtime = runManagedOperation(operation, async ({ signal, update, appendOutput, throwIfCancelled }) => {
    update({ step: 'preflight', progress: 1, message: 'Validando árvore e permissões Linux...' });
    const plan = await buildPlan(source, destination, signal);
    throwIfCancelled();
    appendOutput(`${plan.entries} item(ns), ${plan.totalBytes} byte(s) planejados.`);

    let copiedBytes = 0;
    let completedEntries = 0;
    const totalUnits = Math.max(1, plan.totalBytes || plan.entries);
    const report = (message) => {
      const units = plan.totalBytes ? copiedBytes : completedEntries;
      update({
        step: 'copying',
        progress: Math.max(2, Math.min(98, Math.round((units / totalUnits) * 96) + 2)),
        message,
      });
    };

    try {
      for (const directory of plan.directories) {
        throwIfCancelled();
        await wslFilesService.request('fs.mkdir', { path: directory.destination, mode: directory.mode }, 10000);
        completedEntries += 1;
        if (!plan.totalBytes) report(`Criando ${directory.destination.at(-1)}...`);
      }

      for (const file of plan.files) {
        throwIfCancelled();
        let offset = 0;
        let first = true;
        if (file.size === 0) {
          await wslFilesService.request('fs.write', {
            path: file.destination,
            offset: 0,
            data: '',
            truncate: true,
            mode: file.mode,
          }, 15000);
        }
        while (offset < file.size) {
          throwIfCancelled();
          const read = await wslFilesService.request('fs.read', {
            path: file.source,
            offset,
            limit: Math.min(CHUNK_SIZE, file.size - offset),
          }, 15000);
          if (!read || typeof read.data !== 'string' || !Number.isSafeInteger(read.bytes) || read.bytes < 0) {
            throw Object.assign(new Error('Leitura Linux retornou um bloco inválido.'), { code: 'FILES_READ_FAILED' });
          }
          if (read.bytes === 0 && !read.eof) throw Object.assign(new Error('Leitura Linux não avançou.'), { code: 'FILES_READ_FAILED' });
          await wslFilesService.request('fs.write', {
            path: file.destination,
            offset,
            data: read.data,
            truncate: first,
            mode: file.mode,
          }, 15000);
          first = false;
          offset += read.bytes;
          copiedBytes += read.bytes;
          report(`Copiando ${file.source.at(-1)}...`);
        }
        completedEntries += 1;
      }
      throwIfCancelled();
      update({ step: 'verifying', progress: 99, message: 'Verificando destino Linux...' });
      const destinationEntry = await getEntry(destination);
      if (destinationEntry.kind !== plan.root.kind) throw Object.assign(new Error('Destino não corresponde ao tipo de origem.'), { code: 'FILES_VERIFY_FAILED' });
      return { copiedBytes, entries: plan.entries };
    } catch (error) {
      await rollbackDestination(destination);
      throw error;
    }
  }, {
    successMessage: 'Cópia Linux concluída e verificada.',
    onCancelled: async () => rollbackDestination(destination),
    onFailure: async () => rollbackDestination(destination),
  });

  runtime.promise.catch(() => {});
  return runtime.operation;
}
