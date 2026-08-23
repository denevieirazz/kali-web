import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const execFileAsync = promisify(execFile);
const WSL_EXE = 'C:\\WINDOWS\\System32\\wsl.exe';

const CONFIG_DIR = path.resolve('runtime');
const CONFIG_FILE = path.join(CONFIG_DIR, 'distro-config.json');

const KNOWN_METADATA = {
  'kali-linux': {
    name: 'Kali Linux',
    icon: '🐉',
    category: 'Segurança & Pentest',
    description: 'Ambiente completo de auditoria, pentest e ferramentas defensivas/ofensivas.',
    sizeEstimateMB: 1800,
  },
  'ubuntu': {
    name: 'Ubuntu',
    icon: '🐧',
    category: 'Desenvolvimento & IA',
    description: 'Distribuição padrão para engenharia, Docker, bibliotecas e produtividade.',
    sizeEstimateMB: 650,
  },
  'ubuntu-24.04': {
    name: 'Ubuntu 24.04 LTS',
    icon: '🐧',
    category: 'Desenvolvimento & IA',
    description: 'Versão LTS moderna do Ubuntu com suporte de longo prazo e estabilidade máxima.',
    sizeEstimateMB: 650,
  },
  'ubuntu-22.04': {
    name: 'Ubuntu 22.04 LTS',
    icon: '🐧',
    category: 'Desenvolvimento',
    description: 'Versão LTS estável do Ubuntu compatível com softwares legados.',
    sizeEstimateMB: 620,
  },
  'debian': {
    name: 'Debian GNU/Linux',
    icon: '🍥',
    category: 'Geral & Minimalista',
    description: 'Distribuição leve e estável com baixo consumo de memória RAM.',
    sizeEstimateMB: 350,
  },
  'archlinux': {
    name: 'Arch Linux',
    icon: '🏹',
    category: 'Avançado & Customizável',
    description: 'Rolling-release de ponta com pacotes recentes e arquitetura personalizável.',
    sizeEstimateMB: 450,
  },
  'fedoralinux-44': {
    name: 'Fedora Linux 44',
    icon: '🎩',
    category: 'Inovação & Enterprise',
    description: 'Ambiente de ponta da Red Hat com tecnologias modernas.',
    sizeEstimateMB: 750,
  },
  'fedoralinux-43': {
    name: 'Fedora Linux 43',
    icon: '🎩',
    category: 'Inovação & Enterprise',
    description: 'Ambiente Fedora estável.',
    sizeEstimateMB: 700,
  },
  'opensuse-tumbleweed': {
    name: 'openSUSE Tumbleweed',
    icon: '🦎',
    category: 'Desenvolvimento & Servidor',
    description: 'Rolling release poderosa com ferramentas de administração YaST.',
    sizeEstimateMB: 800,
  },
  'alpine': {
    name: 'Alpine Linux',
    icon: '📦',
    category: 'Ultra Leve & Instantâneo',
    description: 'Distribuição minimalista em musl libc, consome apenas 20MB de RAM.',
    sizeEstimateMB: 50,
  },
};

/**
 * Garante e retorna a estrutura do CloudOS Home unificada no Windows.
 */
export function getCloudOSHome() {
  const userHome = os.homedir();
  const cloudosHome = path.join(userHome, 'CloudOS');

  const subfolders = [
    'Desktop',
    'Documents',
    'Downloads',
    'Pictures',
    'Videos',
    'Projects',
    'Workspace',
  ];

  if (!fs.existsSync(cloudosHome)) {
    try {
      fs.mkdirSync(cloudosHome, { recursive: true });
    } catch {}
  }

  const paths = { root: cloudosHome };
  for (const folder of subfolders) {
    const p = path.join(cloudosHome, folder);
    if (!fs.existsSync(p)) {
      try {
        fs.mkdirSync(p, { recursive: true });
      } catch {}
    }
    paths[folder.toLowerCase()] = p;
  }

  return paths;
}

/**
 * Retorna a distribuição Linux ativa configurada.
 */
export function getActiveDistro() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      if (data?.activeDistro && typeof data.activeDistro === 'string') {
        return data.activeDistro;
      }
    }
  } catch {}
  return 'kali-linux';
}

/**
 * Salva a distribuição Linux ativa.
 */
export function setActiveDistro(distroName) {
  if (!distroName || typeof distroName !== 'string') {
    throw new Error('Nome de distribuição inválido.');
  }
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
  const config = {
    activeDistro: distroName.trim(),
    updatedAt: new Date().toISOString(),
  };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
  return config;
}

/**
 * Lista as distribuições instaladas no host via `wsl.exe -l -v`.
 */
export async function listInstalledDistros() {
  try {
    const { stdout } = await execFileAsync(WSL_EXE, ['-l', '-v'], { windowsHide: true, timeout: 5000 });
    // Remove null bytes se vier em UTF-16
    const cleanStr = String(stdout || '').replace(/\0/g, '');
    const lines = cleanStr.split(/\r?\n/).filter(l => l.trim().length > 0);

    const distros = [];
    const activeCurrent = getActiveDistro();

    for (let i = 1; i < lines.length; i++) {
      const line = lines[i].trim();
      const isDefault = line.startsWith('*');
      const parts = line.replace(/^\*\s*/, '').trim().split(/\s+/);
      if (parts.length >= 2) {
        const id = parts[0];
        const state = parts[1];
        const version = parts[2] || '2';
        const meta = KNOWN_METADATA[id.toLowerCase()] || {
          name: id,
          icon: '🐧',
          category: 'Linux',
          description: 'Distribuição WSL registrada.',
          sizeEstimateMB: 500,
        };

        distros.push({
          id,
          name: meta.name,
          icon: meta.icon,
          category: meta.category,
          description: meta.description,
          state,
          version,
          isWslDefault: isDefault,
          isActiveInCloudOS: id.toLowerCase() === activeCurrent.toLowerCase(),
        });
      }
    }

    if (distros.length === 0) {
      distros.push({
        id: 'kali-linux',
        name: 'Kali Linux',
        icon: '🐉',
        category: 'Segurança & Pentest',
        description: 'Distribuição padrão do CloudOS.',
        state: 'Running',
        version: '2',
        isWslDefault: true,
        isActiveInCloudOS: true,
      });
    }

    return distros;
  } catch (error) {
    return [
      {
        id: 'kali-linux',
        name: 'Kali Linux',
        icon: '🐉',
        category: 'Segurança & Pentest',
        description: 'Distribuição padrão do CloudOS.',
        state: 'Running',
        version: '2',
        isWslDefault: true,
        isActiveInCloudOS: true,
      },
    ];
  }
}

/**
 * Lista as distribuições disponíveis online via Microsoft Store.
 */
export async function listOnlineDistros() {
  const installed = await listInstalledDistros();
  const installedIds = new Set(installed.map(d => d.id.toLowerCase()));

  try {
    const { stdout } = await execFileAsync(WSL_EXE, ['--list', '--online'], { windowsHide: true, timeout: 8000 });
    const cleanStr = String(stdout || '').replace(/\0/g, '');
    const lines = cleanStr.split(/\r?\n/).filter(l => l.trim().length > 0);

    const online = [];
    let startParsing = false;

    for (const line of lines) {
      if (line.includes('NAME') && line.includes('FRIENDLY NAME')) {
        startParsing = true;
        continue;
      }
      if (!startParsing) continue;

      const trimmed = line.trim();
      if (!trimmed) continue;
      const parts = trimmed.split(/\s{2,}/);
      if (parts.length >= 2) {
        const id = parts[0].trim();
        const friendlyName = parts[1].trim();
        const meta = KNOWN_METADATA[id.toLowerCase()] || {
          name: friendlyName || id,
          icon: '🐧',
          category: 'Linux Distro',
          description: 'Distribuição oficial da Microsoft Store.',
          sizeEstimateMB: 500,
        };

        online.push({
          id,
          name: meta.name || friendlyName,
          friendlyName,
          icon: meta.icon,
          category: meta.category,
          description: meta.description,
          sizeEstimateMB: meta.sizeEstimateMB,
          isInstalled: installedIds.has(id.toLowerCase()),
        });
      }
    }

    if (online.length === 0) throw new Error('Parsing vazio');
    return online;
  } catch {
    // Fallback com catálogo curado
    return Object.entries(KNOWN_METADATA).map(([id, meta]) => ({
      id,
      name: meta.name,
      friendlyName: meta.name,
      icon: meta.icon,
      category: meta.category,
      description: meta.description,
      sizeEstimateMB: meta.sizeEstimateMB,
      isInstalled: installedIds.has(id.toLowerCase()),
    }));
  }
}

/**
 * Dispara a instalação de uma nova distribuição WSL via CLI.
 */
export async function installDistro(distroName) {
  if (!distroName || typeof distroName !== 'string') {
    throw new Error('Nome da distribuição obrigatório.');
  }

  const cleanName = distroName.trim();
  // Inicia em background
  const child = execFile(WSL_EXE, ['--install', '-d', cleanName, '--no-launch'], { windowsHide: true });
  return {
    success: true,
    distro: cleanName,
    message: `Instalação de ${cleanName} iniciada em segundo plano.`,
  };
}

/**
 * Remove e cancela o registro de uma distribuição WSL.
 */
export async function unregisterDistro(distroName) {
  if (!distroName || typeof distroName !== 'string') {
    throw new Error('Nome de distribuição inválido.');
  }
  const cleanName = distroName.trim();
  await execFileAsync(WSL_EXE, ['--unregister', cleanName], { windowsHide: true, timeout: 15000 });
  return { success: true, distro: cleanName, message: `Distribuição ${cleanName} removida com sucesso.` };
}

/**
 * Importa uma imagem personalizada de RootFS (.tar / .tar.gz) para o WSL.
 */
export async function importDistro(distroName, installLocation, tarPath) {
  if (!distroName || !installLocation || !tarPath) {
    throw new Error('Parâmetros de importação incompletos.');
  }
  const cleanName = distroName.trim();
  await execFileAsync(WSL_EXE, ['--import', cleanName, installLocation, tarPath, '--version', '2'], { windowsHide: true, timeout: 30000 });
  return { success: true, distro: cleanName, message: `Distribuição ${cleanName} importada com sucesso.` };
}

