function normalizePath(path) {
  if (!Array.isArray(path)) return [];
  return path.map(part => String(part).trim()).filter(Boolean).slice(0, 64);
}

function samePath(left, right) {
  return left.length === right.length && left.every((part, index) => part === right[index]);
}

function isPrefix(prefix, candidate) {
  return prefix.length <= candidate.length && prefix.every((part, index) => candidate[index] === part);
}

export function validatePastePath({ sourcePath, entryName, kind, destinationPath, action } = {}) {
  const source = normalizePath(sourcePath);
  const destination = normalizePath(destinationPath);
  const safeName = typeof entryName === 'string' ? entryName.trim() : '';
  const sameDirectory = samePath(source, destination);

  if (!safeName) return { ok: false, sameDirectory, reason: 'Item de origem inválido.' };
  if (kind === 'directory' && isPrefix([...source, safeName], destination)) {
    return { ok: false, sameDirectory, reason: 'Uma pasta não pode ser copiada ou movida para dentro dela mesma.' };
  }
  if (action === 'cut' && sameDirectory) return { ok: true, sameDirectory: true, reason: '' };
  return { ok: true, sameDirectory, reason: '' };
}
