import { execSync } from 'child_process';
import path from 'path';

const WSL_EXE = 'C:\\Windows\\System32\\wsl.exe';

export function getRawWslListOutput() {
  try {
    const raw = execSync(`${WSL_EXE} --list --verbose`, { timeout: 3000 });
    let text = raw.toString('utf16le');
    if (!text || text.includes('\0')) {
      text = raw.toString('utf8').replace(/\0/g, '');
    }
    return text.replace(/^\uFEFF/, '');
  } catch (e) {
    return '';
  }
}

export function parseWslListOutput(output) {
  const lines = output
    .split(/\r?\n/)
    .map(line => line.replace(/\0/g, '').trim())
    .filter(Boolean);

  const distros = [];

  for (const line of lines) {
    // Pular cabeçalho "NAME STATE VERSION" ou mensagens de status
    if (line.toUpperCase().includes('NAME') && line.toUpperCase().includes('STATE')) continue;
    if (line.toLowerCase().startsWith('distribui') || line.toLowerCase().startsWith('default')) continue;

    const isDefault = line.startsWith('*');
    const cleanLine = line.replace(/^\*\s*/, '').trim();
    const parts = cleanLine.split(/\s+/);

    if (parts.length >= 1) {
      const name = parts[0];
      // Impedir lixo ou palavras reservadas
      if (!name || name.length < 2) continue;

      const state = parts.length >= 2 ? parts[1] : 'Unknown';
      const rawVersion = parts.length >= 3 ? parseInt(parts[2], 10) : null;
      const version = !isNaN(rawVersion) ? rawVersion : null;

      distros.push({
        name,
        version,
        state,
        isDefault
      });
    }
  }

  return distros;
}

export function listInstalled() {
  const output = getRawWslListOutput();
  return parseWslListOutput(output);
}

export function getDefault() {
  const distros = listInstalled();
  const def = distros.find(d => d.isDefault);
  if (def) return def.name;
  return distros.length > 0 ? distros[0].name : null;
}

export function getPreferred() {
  const distros = listInstalled();
  const kali = distros.find(d => d.name.toLowerCase() === 'kali-linux');
  if (kali) return kali.name;
  const def = distros.find(d => d.isDefault);
  if (def) return def.name;
  return distros.length > 0 ? distros[0].name : null;
}

export function normalizeName(name) {
  if (!name || typeof name !== 'string') return '';
  return name.trim();
}

export function isInstalled(name) {
  const norm = normalizeName(name).toLowerCase();
  if (!norm) return false;
  const distros = listInstalled();
  return distros.some(d => d.name.toLowerCase() === norm);
}

export function validateAllowlisted(name) {
  const norm = normalizeName(name);
  if (!norm) return false;
  // Segurança estrita: apenas alfanuméricos e hífens
  if (!/^[a-zA-Z0-9._-]+$/.test(norm)) return false;
  return isInstalled(norm);
}
