import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WSL_EXE, getWslSnapshot, safeChildEnvironment, validateInstalledAsync } from '../wsl/distroService.js';

const execFileAsync = promisify(execFile);

export const KALI_TOOL_MANIFEST = Object.freeze([
  { id: 'nmap', command: 'nmap', name: 'Nmap', category: 'recon', description: 'Descoberta e inventário de rede.', guiAliases: [] },
  { id: 'masscan', command: 'masscan', name: 'Masscan', category: 'recon', description: 'Scanner de portas de alta velocidade.', guiAliases: [] },
  { id: 'netdiscover', command: 'netdiscover', name: 'Netdiscover', category: 'recon', description: 'Descoberta ARP em redes locais.', guiAliases: [] },
  { id: 'dnsenum', command: 'dnsenum', name: 'dnsenum', category: 'recon', description: 'Enumeração DNS.', guiAliases: [] },
  { id: 'amass', command: 'amass', name: 'Amass', category: 'osint', description: 'Mapeamento de superfície e DNS.', guiAliases: [] },
  { id: 'theharvester', command: 'theHarvester', name: 'theHarvester', category: 'osint', description: 'Coleta de fontes públicas e OSINT.', guiAliases: [] },
  { id: 'whois', command: 'whois', name: 'WHOIS', category: 'osint', description: 'Consulta de registros públicos de domínio.', guiAliases: [] },
  { id: 'sherlock', command: 'sherlock', name: 'Sherlock', category: 'osint', description: 'Pesquisa de usernames em serviços públicos.', guiAliases: [] },
  { id: 'holehe', command: 'holehe', name: 'Holehe', category: 'osint', description: 'Verificação OSINT de presença de e-mail.', guiAliases: [] },
  { id: 'nikto', command: 'nikto', name: 'Nikto', category: 'web', description: 'Auditoria de configuração de servidores web.', guiAliases: [] },
  { id: 'gobuster', command: 'gobuster', name: 'Gobuster', category: 'web', description: 'Enumeração de conteúdo e DNS.', guiAliases: [] },
  { id: 'feroxbuster', command: 'feroxbuster', name: 'Feroxbuster', category: 'web', description: 'Descoberta recursiva de conteúdo web.', guiAliases: [] },
  { id: 'sqlmap', command: 'sqlmap', name: 'sqlmap', category: 'web', description: 'Ferramenta de auditoria de SQL injection.', guiAliases: [] },
  { id: 'wfuzz', command: 'wfuzz', name: 'Wfuzz', category: 'web', description: 'Fuzzing de aplicações web.', guiAliases: [] },
  { id: 'burpsuite', command: 'burpsuite', name: 'Burp Suite', category: 'web', description: 'Proxy e suíte de testes web.', guiAliases: ['burp suite', 'burpsuite'] },
  { id: 'hydra', command: 'hydra', name: 'Hydra', category: 'credentials', description: 'Auditoria de autenticação online.', guiAliases: [] },
  { id: 'john', command: 'john', name: 'John the Ripper', category: 'credentials', description: 'Auditoria offline de hashes.', guiAliases: ['john the ripper'] },
  { id: 'hashcat', command: 'hashcat', name: 'Hashcat', category: 'credentials', description: 'Auditoria acelerada de hashes.', guiAliases: [] },
  { id: 'msfconsole', command: 'msfconsole', name: 'Metasploit Framework', category: 'frameworks', description: 'Framework modular de validação de vulnerabilidades.', guiAliases: ['metasploit'] },
  { id: 'searchsploit', command: 'searchsploit', name: 'SearchSploit', category: 'frameworks', description: 'Pesquisa local de referências Exploit-DB.', guiAliases: [] },
  { id: 'wireshark', command: 'wireshark', name: 'Wireshark', category: 'network', description: 'Análise de tráfego de rede.', guiAliases: ['wireshark'] },
  { id: 'tcpdump', command: 'tcpdump', name: 'tcpdump', category: 'network', description: 'Captura e inspeção de pacotes.', guiAliases: [] },
  { id: 'aircrack-ng', command: 'aircrack-ng', name: 'Aircrack-ng', category: 'wireless', description: 'Suite de auditoria de redes sem fio.', guiAliases: ['aircrack-ng'] },
  { id: 'reaver', command: 'reaver', name: 'Reaver', category: 'wireless', description: 'Ferramenta de avaliação WPS.', guiAliases: [] },
  { id: 'binwalk', command: 'binwalk', name: 'Binwalk', category: 'forensics', description: 'Inspeção de firmware e arquivos binários.', guiAliases: [] },
  { id: 'exiftool', command: 'exiftool', name: 'ExifTool', category: 'forensics', description: 'Inspeção de metadados de arquivos.', guiAliases: [] },
  { id: 'autopsy', command: 'autopsy', name: 'Autopsy', category: 'forensics', description: 'Análise forense com interface gráfica.', guiAliases: ['autopsy'] },
  { id: 'ghidra', command: 'ghidraRun', name: 'Ghidra', category: 'reverse', description: 'Engenharia reversa e análise de binários.', guiAliases: ['ghidra'] },
  { id: 'radare2', command: 'r2', name: 'radare2', category: 'reverse', description: 'Framework de engenharia reversa.', guiAliases: ['radare2'] },
]);

const INVENTORY_SCRIPT = [
  'for tool in "$@"; do',
  '  if command -v "$tool" >/dev/null 2>&1; then',
  '    printf "%s\\0371\\n" "$tool"',
  '  else',
  '    printf "%s\\0370\\n" "$tool"',
  '  fi',
  'done'
].join('\n');

export function parseToolInventory(output, manifest = KALI_TOOL_MANIFEST) {
  const statusByCommand = new Map();
  for (const rawLine of String(output || '').split(/\r?\n/)) {
    const [command, rawInstalled] = rawLine.split('\x1f');
    if (!command) continue;
    statusByCommand.set(command, rawInstalled === '1');
  }
  return manifest.map((tool) => ({
    id: tool.id,
    command: tool.command,
    name: tool.name,
    category: tool.category,
    description: tool.description,
    guiAliases: [...tool.guiAliases],
    installed: statusByCommand.get(tool.command) === true
  }));
}

export function publicToolManifest() {
  return KALI_TOOL_MANIFEST.map((tool) => ({
    id: tool.id,
    command: tool.command,
    name: tool.name,
    category: tool.category,
    description: tool.description,
    guiAliases: [...tool.guiAliases],
    installed: false
  }));
}

export async function getKaliToolInventory(requestedDistribution) {
  const snapshot = await getWslSnapshot();
  if (!snapshot.operational) {
    return {
      operational: false,
      distribution: null,
      errorCode: snapshot.errorCode || 'WSL_NOT_OPERATIONAL',
      error: snapshot.error || 'WSL não está operacional.',
      tools: publicToolManifest()
    };
  }

  const distribution = typeof requestedDistribution === 'string' && requestedDistribution.trim()
    ? requestedDistribution.trim()
    : snapshot.preferred || snapshot.default;
  if (!distribution || !await validateInstalledAsync(distribution)) {
    const error = new Error('Distribuição WSL não encontrada.');
    error.code = 'DISTRO_NOT_INSTALLED';
    throw error;
  }

  const args = [
    '--distribution', distribution,
    '--exec', '/bin/sh', '-c', INVENTORY_SCRIPT,
    'cloudos-tool-inventory',
    ...KALI_TOOL_MANIFEST.map((tool) => tool.command)
  ];

  try {
    const { stdout } = await execFileAsync(WSL_EXE, args, {
      encoding: 'utf8',
      env: safeChildEnvironment(),
      timeout: 15_000,
      windowsHide: true,
      maxBuffer: 256 * 1024
    });
    return {
      operational: true,
      distribution,
      errorCode: null,
      error: null,
      tools: parseToolInventory(stdout)
    };
  } catch {
    return {
      operational: false,
      distribution,
      errorCode: 'TOOL_INVENTORY_FAILED',
      error: 'Não foi possível consultar o inventário de ferramentas nesta distribuição.',
      tools: publicToolManifest()
    };
  }
}
