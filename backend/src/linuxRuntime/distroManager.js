import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { validateInstalledAsync } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);
const WSL_EXE = 'C:\\WINDOWS\\System32\\wsl.exe';

const CONFIG_DIR = path.resolve('runtime');
const CONFIG_FILE = path.join(CONFIG_DIR, 'distro-config.json');
const WSL_INSTALL_TIMEOUT_MS = 10 * 60 * 1000;
const WSL_REGISTRATION_TIMEOUT_MS = 2 * 60 * 1000;

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

const SAFE_DISTRO_NAME = /^[a-zA-Z0-9._-]+$/;

function cleanWslString(str) {
  if (!str) return '';
  return String(str).replace(/\0/g, '').replace(/[^\x20-\x7E\u00A0-\u00FF]/g, ' ').replace(/\s+/g, ' ').trim();
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function provisioningError(message, code, cause) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = 503;
  if (cause) error.cause = cause;
  return error;
}

async function waitForDistroRegistration(distroName, timeoutMs = WSL_REGISTRATION_TIMEOUT_MS) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (await validateInstalledAsync(distroName)) return true;
    await sleep(1000);
  }
  return false;
}

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

  fs.mkdirSync(cloudosHome, { recursive: true });

  const paths = { root: cloudosHome };
  for (const folder of subfolders) {
    const folderPath = path.join(cloudosHome, folder);
    fs.mkdirSync(folderPath, { recursive: true });
    paths[folder.toLowerCase()] = folderPath;
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
  const cleanName = validateDistroIdentifier(distroName);
  fs.mkdirSync(CONFIG_DIR, { recursive: true });
  const config = {
    activeDistro: cleanName,
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
    const cleanStr = String(stdout || '').replace(/\0/g, '');
    const lines = cleanStr.split(/\r?\n/).filter(line => line.trim().length > 0);

    const distros = [];
    const activeCurrent = getActiveDistro();

    for (let index = 1; index < lines.length; index += 1) {
      const line = lines[index].trim();
      const isDefault = line.startsWith('*');
      const parts = line.replace(/^\*\s*/, '').trim().split(/\s+/);
      if (parts.length < 2) continue;

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

    return distros;
  } catch {
    return [];
  }
}

/**
 * Lista as distribuições disponíveis online via Microsoft Store.
 */
export async function listOnlineDistros() {
  const installed = await listInstalledDistros();
  const installedIds = new Set(installed.map(distro => distro.id.toLowerCase()));

  try {
    const { stdout } = await execFileAsync(WSL_EXE, ['--list', '--online'], { windowsHide: true, timeout: 8000 });
    const cleanStr = String(stdout || '').replace(/\0/g, '');
    const lines = cleanStr.split(/\r?\n/).filter(line => line.trim().length > 0);

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
      if (parts.length < 2) continue;

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

    if (online.length === 0) throw new Error('Parsing vazio');
    return online;
  } catch {
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

export function validateDistroIdentifier(name) {
  if (!name || typeof name !== 'string') {
    const error = new Error('Nome de distribuição inválido.');
    error.statusCode = 400;
    error.code = 'INVALID_DISTRO_NAME';
    throw error;
  }
  const clean = name.trim();
  if (!SAFE_DISTRO_NAME.test(clean) || clean.length > 64) {
    const error = new Error('Identificador de distribuição inválido ou contém caracteres não permitidos.');
    error.statusCode = 400;
    error.code = 'INVALID_DISTRO_NAME';
    throw error;
  }
  return clean;
}

/**
 * Dispara a instalação de uma nova distribuição WSL via CLI.
 * Confirma que o processo foi criado; a conclusão é acompanhada pelo fluxo de provisionamento.
 */
export async function installDistro(distroName) {
  const cleanName = validateDistroIdentifier(distroName);
  await new Promise((resolve, reject) => {
    let child;
    try {
      child = execFile(WSL_EXE, ['--install', '-d', cleanName, '--no-launch'], { windowsHide: true });
    } catch (cause) {
      reject(cause);
      return;
    }
    child.once('spawn', resolve);
    child.once('error', reject);
  });
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
  const cleanName = validateDistroIdentifier(distroName);
  try {
    await execFileAsync(WSL_EXE, ['--terminate', cleanName], { windowsHide: true, timeout: 10000 }).catch(() => {});
    await execFileAsync(WSL_EXE, ['--unregister', cleanName], { windowsHide: true, timeout: 20000 });
    return { success: true, distro: cleanName, message: `Distribuição ${cleanName} removida com sucesso.` };
  } catch (err) {
    const rawOut = cleanWslString(err.stdout || err.stderr || err.message);
    if (rawOut.includes('não existe') || rawOut.includes('not found') || rawOut.includes('não tem distribuições')) {
      return { success: true, distro: cleanName, message: `Distribuição ${cleanName} não estava registrada no subsistema.` };
    }
    const error = new Error(`Falha ao desregistrar ${cleanName}: ${rawOut || err.message}`);
    error.statusCode = 500;
    throw error;
  }
}

/**
 * Importa uma imagem personalizada de RootFS (.tar / .tar.gz) para o WSL.
 */
export async function importDistro(distroName, installLocation, tarPath) {
  const cleanName = validateDistroIdentifier(distroName);
  if (!installLocation || !tarPath) {
    const error = new Error('Parâmetros de importação incompletos.');
    error.statusCode = 400;
    throw error;
  }
  await execFileAsync(WSL_EXE, ['--import', cleanName, installLocation, tarPath, '--version', '2'], { windowsHide: true, timeout: WSL_INSTALL_TIMEOUT_MS });
  return { success: true, distro: cleanName, message: `Distribuição ${cleanName} importada com sucesso.` };
}

/**
 * Provisiona o ambiente e garante a estrutura do CloudOS Home para uma distro já registrada.
 */
export async function provisionDistro(distroName) {
  const cleanName = validateDistroIdentifier(distroName || getActiveDistro());
  if (!await validateInstalledAsync(cleanName)) {
    throw provisioningError(`Distribuição WSL "${cleanName}" não encontrada ou não instalada.`, 'DISTRO_NOT_INSTALLED');
  }

  const home = getCloudOSHome();
  setActiveDistro(cleanName);

  return {
    success: true,
    distro: cleanName,
    home,
    steps: [
      { id: 'wsl', label: 'WSL 2 Inicializado', done: true },
      { id: 'distro', label: `Distribuição ${cleanName} registrada`, done: true },
      { id: 'home', label: 'CloudOS Home criado e sincronizado', done: true },
    ],
  };
}

/**
 * Stream de provisionamento real executando comandos no WSL 2, criando VFS e registrando runtime.
 */
export async function* streamProvisionDistro(distroName, mode = 'existing') {
  const cleanName = validateDistroIdentifier(distroName || getActiveDistro());

  yield { step: 'wsl', stepDone: false, progress: 15, log: '[WSL] Verificando subsistema WSL 2 e integridade do host...' };
  if (process.env.NODE_ENV === 'test' && process.env.CLOUDOS_TEST_ROOT) {
    yield { step: 'wsl', stepDone: true, progress: 25, log: '[WSL] WSL 2 Operacional (simulado em teste)' };
  } else {
    try {
      const { stdout: wslStatus } = await execFileAsync(WSL_EXE, ['--status'], { windowsHide: true, timeout: 10000 });
      const firstLine = cleanWslString(String(wslStatus || '').trim().split(/[\r\n]+/)[0]) || 'WSL 2 Operacional';
      yield { step: 'wsl', stepDone: true, progress: 25, log: `[WSL] ${firstLine}` };
    } catch (cause) {
      throw provisioningError('Não foi possível confirmar que o WSL 2 está operacional.', 'WSL_STATUS_FAILED', cause);
    }
  }

  yield { step: 'distro', stepDone: false, progress: 35, log: `[Distro] Preparando distribuição: ${cleanName} (Modo: ${mode})...` };

  if (mode === 'reinstall' && process.env.NODE_ENV !== 'test') {
    yield { step: 'distro', stepDone: false, progress: 40, log: `[Distro] Removendo registro anterior de ${cleanName}...` };
    if (await validateInstalledAsync(cleanName)) {
      await execFileAsync(WSL_EXE, ['--terminate', cleanName], { windowsHide: true, timeout: 10000 }).catch(() => {});
      try {
        await execFileAsync(WSL_EXE, ['--unregister', cleanName], { windowsHide: true, timeout: 30000 });
      } catch (cause) {
        throw provisioningError(`Falha ao remover a instalação anterior de ${cleanName}.`, 'DISTRO_UNREGISTER_FAILED', cause);
      }
    }
  }

  if ((mode === 'new' || mode === 'reinstall') && process.env.NODE_ENV !== 'test') {
    yield { step: 'distro', stepDone: false, progress: 45, log: `[Distro] Instalando ${cleanName}. Downloads do WSL podem levar vários minutos...` };
    try {
      const { stdout: installOut } = await execFileAsync(
        WSL_EXE,
        ['--install', '-d', cleanName, '--no-launch'],
        { windowsHide: true, timeout: WSL_INSTALL_TIMEOUT_MS, maxBuffer: 2 * 1024 * 1024 }
      );
      const installLog = cleanWslString(installOut) || 'Comando de instalação concluído.';
      yield { step: 'distro', stepDone: false, progress: 52, log: `[Distro] ${installLog}` };
    } catch (cause) {
      const detail = cleanWslString(cause?.stderr || cause?.stdout || cause?.message);
      throw provisioningError(`Falha ao instalar ${cleanName}: ${detail || 'o WSL encerrou a instalação com erro.'}`, 'DISTRO_INSTALL_FAILED', cause);
    }

    yield { step: 'distro', stepDone: false, progress: 55, log: `[Distro] Aguardando confirmação do registro de ${cleanName}...` };
    if (!await waitForDistroRegistration(cleanName)) {
      throw provisioningError(`A distribuição ${cleanName} não apareceu como instalada dentro do tempo esperado.`, 'DISTRO_REGISTRATION_TIMEOUT');
    }
  } else if (mode === 'new' || mode === 'reinstall') {
    yield { step: 'distro', stepDone: false, progress: 55, log: `[Distro] Simulação de registro concluída para ${cleanName}.` };
  }

  if (process.env.NODE_ENV !== 'test' && !await validateInstalledAsync(cleanName)) {
    throw provisioningError(`Distribuição WSL "${cleanName}" não encontrada após o provisionamento.`, 'DISTRO_NOT_INSTALLED');
  }

  if (process.env.NODE_ENV !== 'test') {
    try {
      const { stdout: unameOut } = await execFileAsync(WSL_EXE, ['-d', cleanName, '--', 'uname', '-srm'], { windowsHide: true, timeout: 15000 });
      const kernel = cleanWslString(unameOut) || 'Linux';
      setActiveDistro(cleanName);
      yield { step: 'distro', stepDone: true, progress: 60, log: `[Distro] Kernel ativo no Linux: ${kernel}` };
    } catch (cause) {
      throw provisioningError(`A distribuição ${cleanName} foi registrada, mas não iniciou corretamente.`, 'DISTRO_START_FAILED', cause);
    }
  } else {
    setActiveDistro(cleanName);
    yield { step: 'distro', stepDone: true, progress: 60, log: `[Distro] Distribuição ${cleanName} validada.` };
  }

  yield { step: 'home', stepDone: false, progress: 70, log: '[CloudOS Home] Criando estrutura de pastas unificadas no Windows...' };
  let home;
  try {
    home = getCloudOSHome();
  } catch (cause) {
    throw provisioningError('Não foi possível criar o CloudOS Home no perfil do Windows.', 'CLOUDOS_HOME_CREATE_FAILED', cause);
  }
  yield { step: 'home', stepDone: false, progress: 75, log: `[CloudOS Home] Raiz: ${home.root}` };

  if (process.env.NODE_ENV !== 'test') {
    const winUser = os.userInfo().username;
    yield { step: 'home', stepDone: false, progress: 80, log: `[CloudOS Home] Montando ~/CloudOS -> /mnt/c/Users/${winUser}/CloudOS...` };
    try {
      await execFileAsync(
        WSL_EXE,
        ['-d', cleanName, '--', 'bash', '-c', `mkdir -p ~/Desktop ~/Documents ~/Downloads ~/Pictures ~/Videos ~/Projects ~/Workspace && ln -sfn "/mnt/c/Users/${winUser}/CloudOS" ~/CloudOS`],
        { windowsHide: true, timeout: 15000 }
      );
    } catch (cause) {
      throw provisioningError('A distribuição iniciou, mas o CloudOS Home não pôde ser vinculado ao Linux.', 'CLOUDOS_HOME_LINK_FAILED', cause);
    }
  }
  yield { step: 'home', stepDone: true, progress: 85, log: '[CloudOS Home] Sincronização Linux concluída.' };

  yield { step: 'runtime', stepDone: false, progress: 90, log: '[Runtime] Verificando servidor gráfico Xpra e subsistema de janelas...' };
  if (process.env.NODE_ENV !== 'test') {
    try {
      const { stdout: xpraVer } = await execFileAsync(
        WSL_EXE,
        ['-d', cleanName, '--', 'bash', '-c', 'if command -v xpra >/dev/null 2>&1; then xpra --version; else echo XPRA_MISSING; fi'],
        { windowsHide: true, timeout: 10000 }
      );
      const xpraLine = cleanWslString(xpraVer);
      if (xpraLine.includes('XPRA_MISSING')) {
        yield { step: 'runtime', stepDone: true, progress: 92, log: '[Runtime] Xpra ainda não está instalado; o readiness do aplicativo solicitará a preparação antes da abertura.' };
      } else {
        yield { step: 'runtime', stepDone: true, progress: 92, log: `[Runtime] Motor gráfico: ${xpraLine || 'Xpra disponível'}` };
      }
    } catch (cause) {
      throw provisioningError('Não foi possível consultar o runtime gráfico da distribuição.', 'XPRA_RUNTIME_CHECK_FAILED', cause);
    }
  } else {
    yield { step: 'runtime', stepDone: true, progress: 92, log: '[Runtime] Validação gráfica simulada em teste.' };
  }

  yield { step: 'apps', stepDone: false, progress: 96, log: '[Apps] Escaneando catálogo de aplicativos XDG (.desktop)...' };
  if (process.env.NODE_ENV !== 'test') {
    try {
      const { stdout: appCount } = await execFileAsync(
        WSL_EXE,
        ['-d', cleanName, '--', 'bash', '-c', 'find /usr/share/applications -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | wc -l'],
        { windowsHide: true, timeout: 10000 }
      );
      yield { step: 'apps', stepDone: true, progress: 98, log: `[Apps] ${cleanWslString(appCount) || '0'} aplicativos detectados para integração.` };
    } catch (cause) {
      throw provisioningError('Não foi possível validar o catálogo de aplicativos da distribuição.', 'APP_DISCOVERY_CHECK_FAILED', cause);
    }
  } else {
    yield { step: 'apps', stepDone: true, progress: 98, log: '[Apps] Catálogo de aplicativos validado em teste.' };
  }

  yield { done: true, step: 'done', progress: 100, log: '[CloudOS Setup] Concluído! Sistema operacional pronto para uso.' };
}
