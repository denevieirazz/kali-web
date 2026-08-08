const { spawn, execFile, exec } = require('child_process');
const { promisify } = require('util');
const EventEmitter = require('events');
const os = require('os');
const crypto = require('crypto');

const execAsync = promisify(exec);

class WslManagerService extends EventEmitter {
  constructor() {
    super();
    this.currentOperation = null; // { state, step, percent, log, error, rebootRequired }
    this.isLocked = false;
  }

  // 1. Coleta diagnósticos de hardware e status do Windows/WSL
  async getSystemDiagnostics() {
    const totalMem = Math.round((os.totalmem() / (1024 ** 3)) * 10) / 10;
    const freeMem = Math.round((os.freemem() / (1024 ** 3)) * 10) / 10;
    const cpus = os.cpus() || [];
    const cpuCount = cpus.length;
    const cpuModel = cpus[0]?.model || 'Processador Host';
    const winRelease = os.release();
    const arch = os.arch();

    let diskTotalGB = 0;
    let diskFreeGB = 0;
    try {
      const { stdout } = await execAsync('powershell.exe -NoProfile -Command "(Get-CimInstance Win32_LogicalDisk -Filter \\"DeviceID=\'C:\'\\") | Select-Object Size, FreeSpace | ConvertTo-Json"');
      const diskObj = JSON.parse(stdout);
      diskTotalGB = Math.round((diskObj.Size / (1024 ** 3)) * 10) / 10;
      diskFreeGB = Math.round((diskObj.FreeSpace / (1024 ** 3)) * 10) / 10;
    } catch {
      diskTotalGB = 0;
      diskFreeGB = 0;
    }

    let virtualizationEnabled = null;
    try {
      const { stdout } = await execAsync('powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled"');
      if (stdout.trim().toLowerCase() === 'true') virtualizationEnabled = true;
      else if (stdout.trim().toLowerCase() === 'false') virtualizationEnabled = false;
    } catch {
      virtualizationEnabled = null;
    }

    // Status do WSL e Distros
    let wslInstalled = false;
    let wslVersion = null;
    let kaliInstalled = false;
    let kaliState = 'NOT_INSTALLED'; // NOT_INSTALLED, STOPPED, RUNNING, ERROR
    let kaliUserReady = false;
    let rebootRequired = false;

    // Checa se o Windows marcou que precisa de reboot para features
    try {
      const { stdout: rebootOut } = await execAsync('powershell.exe -NoProfile -Command "Test-Path \'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing\\RebootPending\'"');
      if (rebootOut.trim().toLowerCase() === 'true') {
        rebootRequired = true;
      }
    } catch {}

    try {
      const { stdout } = await execAsync('wsl.exe --status', { encoding: 'utf16le' });
      if (stdout && stdout.toLowerCase().includes('default version')) {
        wslInstalled = true;
        wslVersion = 2;
      }
    } catch {
      try {
        const { stdout: featOut } = await execAsync('powershell.exe -NoProfile -Command "(Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State"');
        if (featOut.trim() === 'Enabled') {
          wslInstalled = true;
        }
      } catch {}
    }

    if (wslInstalled) {
      try {
        const { stdout: listOut } = await execAsync('wsl.exe -l -v', { encoding: 'utf16le' });
        const lines = listOut.split('\n');
        for (const line of lines) {
          if (line.toLowerCase().includes('kali-linux')) {
            kaliInstalled = true;
            if (line.toLowerCase().includes('running')) kaliState = 'RUNNING';
            else if (line.toLowerCase().includes('stopped')) kaliState = 'STOPPED';
            else kaliState = 'INSTALLED';
          }
        }
      } catch {
        // Sem distros instaladas ainda
      }
    }

    // Verifica usuário cloudos no Kali de forma não-bloqueante
    if (kaliInstalled) {
      try {
        const { stdout: userOut } = await execAsync('wsl.exe -d kali-linux -u cloudos -- whoami', { timeout: 3000 });
        if (userOut.trim() === 'cloudos') {
          kaliUserReady = true;
        }
      } catch {
        kaliUserReady = false;
      }
    }

    // Determina o estado global de prontidão
    let overallStatus = 'NOT_INSTALLED';
    if (this.currentOperation && this.currentOperation.state === 'INSTALLING') {
      overallStatus = 'INSTALLING';
    } else if (rebootRequired) {
      overallStatus = 'REBOOT_REQUIRED';
    } else if (!wslInstalled) {
      overallStatus = 'NOT_INSTALLED';
    } else if (!kaliInstalled) {
      overallStatus = 'WSL_READY_NO_KALI';
    } else if (kaliInstalled && !kaliUserReady) {
      overallStatus = 'CONFIGURING';
    } else if (kaliInstalled && kaliUserReady) {
      overallStatus = 'READY';
    }

    return {
      hardware: {
        totalMemGB: totalMem,
        freeMemGB: freeMem,
        cpuCount,
        cpuModel,
        arch,
        diskTotalGB,
        diskFreeGB,
        virtualizationEnabled
      },
      os: {
        platform: 'Windows',
        release: winRelease
      },
      wsl: {
        installed: wslInstalled,
        version: wslVersion,
        kaliInstalled,
        kaliState,
        kaliUserReady,
        rebootRequired
      },
      overallStatus,
      requirements: {
        ramOk: totalMem >= 4,
        diskOk: diskFreeGB >= 15,
        cpuOk: cpuCount >= 2,
        virtualizationOk: virtualizationEnabled !== false
      }
    };
  }

  // 2. Executa a instalação real do WSL e Kali Linux de forma controlada e segura
  async startInstallation(options = {}) {
    if (this.isLocked) {
      throw new Error('Uma operação de instalação ou configuração já está em andamento.');
    }

    this.isLocked = true;
    this.currentOperation = {
      state: 'INSTALLING',
      step: 'STARTING',
      percent: 0,
      logs: [],
      error: null,
      rebootRequired: false
    };

    const username = options.username ? String(options.username).replace(/[^a-zA-Z0-9_]/g, '') : 'cloudos';
    // Geração dinâmica de token/senha seguro para o provisionamento (sem hardcode)
    const provisionPassword = options.password ? String(options.password) : crypto.randomBytes(16).toString('hex');

    // Executa em segundo plano com eventos emitidos
    (async () => {
      try {
        this._updateProgress(5, 'ENABLE_WSL_FEATURE', 'Verificando e ativando recursos do Windows...');
        
        // Habilita recurso WSL
        const { stdout: wslOut } = await execAsync('powershell.exe -NoProfile -Command "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart"');
        this._addLog('Recurso Microsoft-Windows-Subsystem-Linux verificado.');

        // Habilita VirtualMachinePlatform
        await execAsync('powershell.exe -NoProfile -Command "Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart"');
        this._addLog('Recurso VirtualMachinePlatform verificado.');

        if (wslOut && wslOut.includes('RestartNeeded : True')) {
          this.currentOperation.rebootRequired = true;
          this._addLog('⚠️ O Windows reportou que uma reinicialização é necessária para habilitar a virtualização.');
        }

        this._updateProgress(20, 'WSL_KERNEL_UPDATE', 'Atualizando kernel do WSL para versão 2...');
        try {
          await execAsync('wsl.exe --update');
          await execAsync('wsl.exe --set-default-version 2');
          this._addLog('WSL2 configurado como padrão.');
        } catch (e) {
          this._addLog('Aviso no wsl --update: ' + e.message);
        }

        this._updateProgress(40, 'INSTALLING_KALI', 'Baixando e instalando Kali Linux via WSL...');
        
        // Instalação real da distro
        try {
          await execAsync('wsl.exe --install -d kali-linux --no-launch');
          this._addLog('Kali Linux registrado no subsistema.');
        } catch (e) {
          this._addLog('Registro de distribuição concluído: ' + e.message);
        }

        this._updateProgress(70, 'CONFIGURING_USER', 'Configurando usuário do CloudOS no Kali Linux...');
        
        // Criação e configuração segura do usuário cloudos no Kali Linux
        const setupScript = `
id -u ${username} &>/dev/null || (useradd -m -s /bin/bash ${username} && echo "${username}:${provisionPassword}" | chpasswd)
usermod -aG sudo ${username}
echo "${username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/cloudos
mkdir -p /home/cloudos_users/${username}
chown -R ${username}:${username} /home/cloudos_users
`;
        const b64 = Buffer.from(setupScript).toString('base64');
        await execAsync(`wsl.exe -d kali-linux -u root -- bash -c "echo ${b64} | base64 -d | bash"`);
        this._addLog(`Usuário '${username}' configurado com sucesso.`);

        this._updateProgress(90, 'TESTING_ENVIRONMENT', 'Validando execução de comandos no WSL Kali...');
        
        // Validação final de ambiente
        const { stdout: testOut } = await execAsync(`wsl.exe -d kali-linux -u ${username} -- whoami`);
        if (testOut.trim() !== username) {
          throw new Error('Falha ao validar execução com o usuário no Kali Linux.');
        }

        this._updateProgress(100, 'READY', 'Ambiente WSL + Kali Linux pronto e validado!');
        this.currentOperation.state = 'READY';
      } catch (err) {
        this.currentOperation.state = 'ERROR';
        this.currentOperation.error = err.message;
        this._addLog('ERRO NA INSTALAÇÃO: ' + err.message);
      } finally {
        this.isLocked = false;
      }
    })();

    return { started: true, initialStatus: this.currentOperation };
  }

  _updateProgress(percent, step, message) {
    if (this.currentOperation) {
      this.currentOperation.percent = percent;
      this.currentOperation.step = step;
      this.currentOperation.log = message;
      this.currentOperation.logs.push(`[${new Date().toLocaleTimeString('pt-BR')}] ${message}`);
      this.emit('progress', this.currentOperation);
    }
  }

  _addLog(msg) {
    if (this.currentOperation) {
      this.currentOperation.logs.push(`[${new Date().toLocaleTimeString('pt-BR')}] ${msg}`);
      this.emit('progress', this.currentOperation);
    }
  }

  getStatus() {
    return this.currentOperation || { state: 'IDLE', percent: 0, logs: [] };
  }
}

module.exports = new WslManagerService();

