// =====================================================================
// 🛡️ CloudOS Setup Wizard - Interactive Engine & Calamares OS Installer
// =====================================================================

const API_BASE = window.location.origin;
let currentStep = 1;
const totalSteps = 6;
let pollInterval = null;

// Dados da instalação
const installData = {
    language: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    edition: 'standard',
    ramGB: 3,
    username: 'cloudos',
    password: 'cloudos123',
    autoLogin: true
};

// Elementos DOM
const steps = document.querySelectorAll('.step');
const stepDots = document.querySelectorAll('.step-dot');
const nextBtn = document.getElementById('next-btn');
const prevBtn = document.getElementById('prev-btn');
const installBtn = document.getElementById('install-btn');
const progressBar = document.getElementById('progress-bar');
const progressText = document.getElementById('progress-text');
const progressLog = document.getElementById('progress-log');
const progressSpeed = document.getElementById('progress-speed');

// Navegação entre etapas
function showStep(step) {
    steps.forEach((el, i) => {
        el.classList.toggle('active', i === step - 1);
    });
    
    stepDots.forEach((dot, i) => {
        dot.classList.remove('active', 'completed');
        if (i < step - 1) {
            dot.classList.add('completed');
        } else if (i === step - 1) {
            dot.classList.add('active');
        }
    });
    
    currentStep = step;
    
    if (prevBtn) prevBtn.style.display = step > 1 ? 'inline-block' : 'none';
    if (nextBtn) nextBtn.style.display = step < totalSteps ? 'inline-block' : 'none';
    if (installBtn) installBtn.style.display = step === totalSteps ? 'inline-block' : 'none';
    
    // Ações específicas por etapa
    if (step === 2) loadDiagnostics();
    if (step === 5) updateSummary();
}

if (nextBtn) {
    nextBtn.addEventListener('click', () => {
        if (currentStep === 4) {
            const passEl = document.getElementById('password-input');
            const confirmPassEl = document.getElementById('confirm-password-input');
            if (passEl && confirmPassEl && passEl.value !== confirmPassEl.value) {
                alert('As senhas não coincidem!');
                return;
            }
        }
        if (currentStep < totalSteps) {
            showStep(currentStep + 1);
        }
    });
}

if (prevBtn) {
    prevBtn.addEventListener('click', () => {
        if (currentStep > 1) {
            showStep(currentStep - 1);
        }
    });
}

// STEP 1: Language
document.querySelectorAll('.language-card').forEach(card => {
    card.addEventListener('click', () => {
        document.querySelectorAll('.language-card').forEach(c => c.classList.remove('selected'));
        card.classList.add('selected');
        installData.language = card.dataset.lang || 'pt-BR';
    });
});

const tzSelect = document.getElementById('timezone-select');
if (tzSelect) {
    tzSelect.addEventListener('change', (e) => {
        installData.timezone = e.target.value;
    });
}

// STEP 2: Diagnostics
async function loadDiagnostics() {
    try {
        const res = await fetch(`${API_BASE}/api/diagnostics`);
        const data = await res.json();
        
        const elRam = document.querySelector('#diag-ram .diag-value');
        const elCpu = document.querySelector('#diag-cpu .diag-value');
        const elDisk = document.querySelector('#diag-disk .diag-value');
        const elWsl = document.querySelector('#diag-wsl .diag-value');
        
        if (elRam) elRam.textContent = `${data.ramTotalGB} GB`;
        if (elCpu) elCpu.textContent = `${data.cpuCores} núcleos`;
        if (elDisk) elDisk.textContent = `${data.diskFreeGB} GB livres`;
        
        if (elWsl) {
            if (data.wslEnabled) {
                elWsl.textContent = '✅ Ativado';
                elWsl.style.color = '#3fb950';
            } else {
                elWsl.textContent = '❌ Não ativado';
                elWsl.style.color = '#f85149';
                const wslWarn = document.getElementById('wsl-warning');
                const enableBtn = document.getElementById('enable-wsl-btn');
                if (wslWarn) wslWarn.style.display = 'flex';
                if (enableBtn) enableBtn.style.display = 'inline-block';
            }
        }
    } catch (err) {
        console.error('Erro ao carregar diagnóstico:', err);
    }
}

const enableWslBtn = document.getElementById('enable-wsl-btn');
if (enableWslBtn) {
    enableWslBtn.addEventListener('click', async () => {
        enableWslBtn.disabled = true;
        enableWslBtn.textContent = '⏳ Ativando...';
        
        try {
            await fetch(`${API_BASE}/api/enable-wsl`, { method: 'POST' });
            enableWslBtn.textContent = '✅ WSL2 Ativado!';
            enableWslBtn.style.background = '#3fb950';
            const wslWarn = document.getElementById('wsl-warning');
            if (wslWarn) wslWarn.style.display = 'none';
        } catch (err) {
            enableWslBtn.textContent = '❌ Erro ao ativar';
            enableWslBtn.style.background = '#f85149';
        }
    });
}

// STEP 3: Edition
document.querySelectorAll('.edition-card').forEach(card => {
    card.addEventListener('click', () => {
        document.querySelectorAll('.edition-card').forEach(c => c.classList.remove('selected'));
        card.classList.add('selected');
        installData.edition = card.dataset.edition || 'standard';
    });
});

// STEP 4: Resources
const ramSlider = document.getElementById('ram-slider');
if (ramSlider) {
    ramSlider.addEventListener('input', (e) => {
        installData.ramGB = parseInt(e.target.value);
        const ramVal = document.getElementById('ram-value');
        if (ramVal) ramVal.textContent = `${installData.ramGB} GB`;
    });
}

document.getElementById('username-input')?.addEventListener('input', (e) => {
    installData.username = e.target.value;
});

document.getElementById('password-input')?.addEventListener('input', (e) => {
    installData.password = e.target.value;
});

document.getElementById('auto-login')?.addEventListener('change', (e) => {
    installData.autoLogin = e.target.checked;
});

// STEP 5: Summary
function updateSummary() {
    const langMap = {
        'pt-BR': 'Português (Brasil)',
        'en-US': 'English (US)',
        'es-ES': 'Español'
    };
    
    const editionMap = {
        'minimal': 'Minimal (~2 GB)',
        'standard': 'Standard (~15 GB)',
        'everything': 'Everything (~64 GB)'
    };
    
    const sumLang = document.getElementById('sum-lang');
    const sumTz = document.getElementById('sum-tz');
    const sumEdition = document.getElementById('sum-edition');
    const sumRam = document.getElementById('sum-ram');
    const sumUser = document.getElementById('sum-user');
    
    if (sumLang) sumLang.textContent = langMap[installData.language] || installData.language;
    if (sumTz) sumTz.textContent = installData.timezone;
    if (sumEdition) sumEdition.textContent = editionMap[installData.edition] || installData.edition;
    if (sumRam) sumRam.textContent = `${installData.ramGB} GB`;
    if (sumUser) sumUser.textContent = installData.username;
}

// STEP 6: Installation
if (installBtn) {
    installBtn.addEventListener('click', async () => {
        installBtn.disabled = true;
        installBtn.textContent = '⏳ Iniciando...';
        
        try {
            const res = await fetch(`${API_BASE}/api/install`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(installData)
            });
            
            const data = await res.json();
            
            if (data.status === 'started') {
                installBtn.textContent = '🚀 Instalando...';
                startPolling();
            } else {
                throw new Error(data.message || 'Erro desconhecido');
            }
        } catch (err) {
            console.error('Erro ao iniciar instalação:', err);
            
            const errorMsg = document.createElement('div');
            errorMsg.style.cssText = `
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                background: rgba(22, 27, 34, 0.95);
                backdrop-filter: blur(12px);
                padding: 30px;
                border-radius: 12px;
                border: 2px solid #f85149;
                color: #c9d1d9;
                font-family: 'Segoe UI', system-ui, sans-serif;
                max-width: 500px;
                text-align: center;
                z-index: 10000;
                box-shadow: 0 10px 40px rgba(0,0,0,0.7);
            `;
            
            errorMsg.innerHTML = `
                <h2 style="margin: 0 0 15px 0; color: #f85149; font-size: 18px;">⚠️ Elevação de Administrador Necessária</h2>
                <p style="margin: 15px 0; line-height: 1.6; font-size: 14px;">
                    Não foi possível iniciar a instalação do subsistema Linux automaticamente.
                </p>
                <div style="margin: 20px 0; padding: 15px; background: rgba(13, 17, 23, 0.8); border-radius: 8px; text-align: left; font-size: 12px; border: 1px solid #30363d;">
                    <strong style="color: #58a6ff;">Como resolver facilmente:</strong><br>
                    1. Feche esta aba do navegador<br>
                    2. Clique com o botão direito no arquivo <code>setup_cloudos.vbs</code><br>
                    3. Selecione <strong>"Executar como Administrador"</strong><br>
                    4. O navegador abrirá automaticamente a instalação ativada
                </div>
                <button onclick="this.parentElement.remove()" style="
                    margin-top: 10px;
                    padding: 10px 24px;
                    background: #238636;
                    color: white;
                    border: none;
                    border-radius: 6px;
                    cursor: pointer;
                    font-size: 13px;
                    font-weight: 600;
                ">Entendi</button>
            `;
            
            document.body.appendChild(errorMsg);
            
            installBtn.disabled = false;
            installBtn.textContent = '🔄 Tentar Novamente';
        }
    });
}

function startPolling() {
    pollInterval = setInterval(async () => {
        try {
            const res = await fetch(`${API_BASE}/api/progress`);
            const data = await res.json();
            
            if (progressBar) {
                progressBar.style.width = `${data.percent}%`;
                progressBar.textContent = `${data.percent}%`;
            }
            if (progressText) progressText.textContent = `${data.percent}% - ${data.status}`;
            if (progressSpeed) progressSpeed.textContent = data.speed || '0 MB/s';
            
            const debugFieldEl = document.getElementById('debug-field');
            if (debugFieldEl && data.debug) {
                debugFieldEl.textContent = `DEBUG: ${data.debug}`;
            }
            
            if (data.log && progressLog) {
                const timestamp = new Date().toLocaleTimeString();
                progressLog.textContent += `[${timestamp}] ${data.log}\n`;
                progressLog.scrollTop = progressLog.scrollHeight;
            }
            
            if (data.percent >= 100) {
                clearInterval(pollInterval);
                const completeBox = document.getElementById('install-complete');
                if (completeBox) completeBox.style.display = 'block';
                
                localStorage.setItem('cloudos_username', installData.username);
                localStorage.setItem('cloudos_password', installData.password);
                
                setTimeout(() => {
                    window.location.href = 'http://localhost:5173';
                }, 3000);
            }
            
            if (data.percent < 0) {
                clearInterval(pollInterval);
                alert('Erro na instalação. Verifique os logs.');
                if (installBtn) {
                    installBtn.disabled = false;
                    installBtn.textContent = '🔄 Tentar Novamente';
                }
            }
        } catch (err) {
            console.error('Erro ao ler progresso:', err);
        }
    }, 250);
}

// =====================================================================
// 🔍 SISTEMA DE DEBUG VISUAL (Botão + Modal + Telemetria em Tempo Real)
// =====================================================================

async function showDebugInfo() {
    try {
        const res = await fetch(`${API_BASE}/api/debug`);
        const debug = await res.json();
        
        const debugModal = document.createElement('div');
        debugModal.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(13, 17, 23, 0.98);
            backdrop-filter: blur(16px);
            padding: 30px;
            border-radius: 12px;
            border: 2px solid #58a6ff;
            color: #c9d1d9;
            font-family: 'Consolas', 'Courier New', monospace;
            max-width: 700px;
            max-height: 80vh;
            overflow-y: auto;
            z-index: 10000;
            box-shadow: 0 10px 40px rgba(0,0,0,0.8);
        `;
        
        debugModal.innerHTML = `
            <h2 style="margin: 0 0 20px 0; color: #58a6ff; font-family: 'Segoe UI', system-ui, sans-serif; font-size: 20px;">🔍 Debug do Servidor CloudOS</h2>
            <div style="background: rgba(22, 27, 34, 0.8); padding: 15px; border-radius: 8px; margin-bottom: 15px; border: 1px solid #30363d; font-size: 13px;">
                <p style="margin: 4px 0;"><strong>Servidor:</strong> ${debug.serverRunning ? '✅ Rodando' : '❌ Parado'}</p>
                <p style="margin: 4px 0;"><strong>Porta Ativa:</strong> ${debug.port}</p>
                <p style="margin: 4px 0;"><strong>Caminho:</strong> ${debug.installerPath}</p>
                <p style="margin: 4px 0;"><strong>progress.json:</strong> ${debug.progressFileExists ? '✅ Existe' : '❌ Não existe'}</p>
                <p style="margin: 4px 0;"><strong>Worker (_install_worker.ps1):</strong> ${debug.workerExists ? '✅ Existe' : '❌ Não existe'}</p>
                <p style="margin: 4px 0;"><strong>Log File:</strong> ${debug.logFile}</p>
            </div>
            <div style="background: rgba(22, 27, 34, 0.8); padding: 15px; border-radius: 8px; border: 1px solid #30363d;">
                <h3 style="margin: 0 0 10px 0; color: #7ee787; font-size: 14px;">Últimos Logs do Servidor:</h3>
                <pre style="font-size: 11px; line-height: 1.5; color: #7ee787; white-space: pre-wrap; margin: 0; max-height: 200px; overflow-y: auto;">${(debug.lastLogs || []).join('\n')}</pre>
            </div>
            <button onclick="this.parentElement.remove()" style="
                margin-top: 20px;
                padding: 10px 30px;
                background: #58a6ff;
                color: white;
                border: none;
                border-radius: 6px;
                cursor: pointer;
                font-size: 14px;
                font-weight: 600;
                width: 100%;
            ">Fechar Debug</button>
        `;
        
        document.body.appendChild(debugModal);
    } catch (err) {
        alert('Erro ao carregar telemetria de debug: ' + err.message);
    }
}

// Botão de Debug flutuante no canto inferior direito
const debugBtn = document.createElement('button');
debugBtn.textContent = '🔍 Debug';
debugBtn.style.cssText = `
    position: fixed;
    bottom: 20px;
    right: 20px;
    padding: 10px 20px;
    background: rgba(88, 166, 255, 0.15);
    border: 1px solid #58a6ff;
    color: #58a6ff;
    border-radius: 6px;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    z-index: 9999;
    transition: all 0.2s ease;
`;
debugBtn.onmouseover = () => { debugBtn.style.background = 'rgba(88, 166, 255, 0.3)'; };
debugBtn.onmouseout = () => { debugBtn.style.background = 'rgba(88, 166, 255, 0.15)'; };
debugBtn.onclick = showDebugInfo;
document.body.appendChild(debugBtn);

// Campo de Debug abaixo da barra de progresso
const installProgContainer = document.querySelector('.install-progress');
if (installProgContainer) {
    const debugField = document.createElement('div');
    debugField.id = 'debug-field';
    debugField.style.cssText = `
        margin-top: 10px;
        padding: 10px;
        background: rgba(13, 17, 23, 0.8);
        border: 1px solid #30363d;
        border-radius: 6px;
        font-family: 'Consolas', 'Courier New', monospace;
        font-size: 11px;
        color: #8b949e;
    `;
    debugField.textContent = 'DEBUG: Aguardando início...';
    installProgContainer.appendChild(debugField);
}

// Inicialização
showStep(1);
