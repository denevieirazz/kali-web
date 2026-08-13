# CloudOS - Master Handoff & Estado Atual do Sistema

## 1. Visão Geral e Arquitetura

O **CloudOS** é um ambiente de desktop híbrido unificado para Windows, combinando a flexibilidade visual de uma interface moderna em React com a potência nativa do ecossistema Windows (WPF/.NET 8 + WebView2) e Linux (WSL2 / WSLg).

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CloudOS.Host (WPF / .NET 8)                     │
│ ┌────────────────────────────────────────────────────────────────────┐ │
│ │                  Microsoft Edge WebView2 (Frontend)                │ │
│ │  React 19 + TypeScript + CSS Modules (Desktop UI, Window Manager)  │ │
│ └───────────────────▲────────────────────────────▲───────────────────┘ │
│                     │ PostMessage / JSON Bridge  │ REST / WebSockets   │
│                     ▼                            ▼                     │
│ ┌────────────────────────────────────┐ ┌─────────────────────────────┐ │
│ │   Native Bridge & Hub Controller   │ │    CloudOS Backend (Node)   │ │
│ │  - Win32 Process / HWND Manager    │ │  - Fastify / SQLite / JSON  │ │
│ │  - Win32 Docking & Reparenting     │ │  - Auth & Account Recovery  │ │
│ │  - WSL/WSLg Lifecycle & Windows    │ │  - PTY Terminal & App Catalog│ │
│ └────────────────────────────────────┘ └─────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Subsistemas e Recursos

### 2.1. Frontend (React 19 + TypeScript)
- **Window Management System**: Sistema de janelas com stacking order, minimização, maximização, snap e foco.
- **NativeAppDock & Contract**: Contrato tipado (`nativeWindowContract.d.ts`, `nativeWindowContract.js`) para gerenciar ciclos de vida de janelas nativas dockadas no canvas web.
- **Terminal Emulator**: Integração com XTerm.js conectado via WebSockets com pseudoterminais (pty) no backend.
- **App Catalog & Store**: Central de aplicativos Linux e utilitários integrados.

### 2.2. Backend (Node.js)
- **Engine**: API REST e WebSockets usando Fastify.
- **Autenticação e Recuperação de Conta**:
  - Mecanismo seguro de migração e fallback de contas legadas.
  - Validação estrita de credenciais com criptografia (bcrypt/argon2).
  - Fluxo de recuperação de senha com perguntas de segurança / tokens de sessão sem sobreposição de estado inválido.
- **App Catalog Service**: Validação e saneamento do catálogo de apps instaláveis no ambiente Linux.
- **Configuração de Origens Seguras**: Restrição estrita de CORS e origens nativas permitidas (`http://127.0.0.1`, `http://localhost`, esquemas customizados do host).

### 2.3. Host Desktop (WPF / .NET 8 / WebView2)
- **Supervisor de Runtime (`CloudOsRuntimeSupervisor`)**:
  - Inicialização orquestrada de backend, detecção de portas dinâmicas e monitoramento de saúde de processos.
  - Coordenação de instância única (`SingleInstanceCoordinator`).
- **Bridge Nativa (`WebMessageBridge`)**:
  - Comunicação bidirecional assíncrona entre o JavaScript da WebView2 e o C# nativo via `window.chrome.webview.postMessage`.
  - Tratamento de mensagens tipadas para janelas, shells e processos.
- **Gerenciador Nativo Win32 & WSLg (`NativeWindowManager`)**:
  - Gerenciamento de HWNDs e processos filhos.
  - Docking de janelas nativas Win32 e janelas X11/Wayland (WSLg) dentro de áreas demarcadas pelo frontend (`NativeAppDock`).
  - Suporte a monitoramento de foco, fechamento automático e restauração de posição.

---

## 3. Estado do Banco de Dados e Isolamento
- O banco de dados do usuário e configurações ativas residem em:
  `%LOCALAPPDATA%\CloudOS\data\cloudos.json` (ou `.sqlite`).
- **Isolamento**: O repositório git **nunca** versiona nem sobrescreve a pasta de dados reais de produção nem credenciais de instâncias locais.

---

## 4. Branches Principais e Fluxo Git
- `main`: Branch de release / produção.
- `fix/forgot-account-password`: Branch de trabalho com as correções estruturais de autenticação, catalogação de apps e contrato de docking nativo.
- `sync/cloudos-current-state`: Branch de consolidação e espelhamento do estado atual completo para revisão e integração.

---

## 5. Instruções de Inicialização, Build e Testes

### Instalação de Dependências
```bash
npm install
```

### Validação e Testes
```bash
# Análise estática
npm run lint

# Build de produção do frontend
npm run build

# Testes unitários / de integração
npm test
node scripts/run-node-tests.js frontend/test

# Testes de ponta a ponta
npm run test:e2e
```

### Compilação do Host Desktop (.NET 8)
```bash
dotnet build desktop/CloudOS.Host/CloudOS.Host.csproj -c Release
```

---

## 6. Recursos Experimentais vs. Estáveis

| Recurso | Status | Descrição |
| :--- | :--- | :--- |
| **Auth & Recuperação de Conta** | Estável | Fluxo completo de login, troca de senha e recuperação segura. |
| **Terminal Web PTY** | Estável | Sessão interativa conectada ao backend e shell configurado. |
| **Gerenciador de Janelas Web** | Estável | Renderização fluida, redimensionamento, foco e snapping. |
| **Docking Win32 / WSLg** | Estável / Em Evolução | Embed de HWNDs externos em bounds definidos via React bridge. |
| **Instalação Automática de Distros WSL** | Experimental | Script e UI para provisionamento assistido de Kali/Debian/Ubuntu. |
| **Shell Mode Total (Windows Shell replacement)** | Em Planejamento | Modos de encapsulamento seguro descritos em `SHELL-MODE-PLAN.md`. |

---

## 7. Limitações e Bugs Conhecidos
1. **DPI Scaling em Janelas WSLg Dockadas**:
   - Em configurações multi-monitor com escalas DPI mistas (ex: 125% e 100%), o cálculo de retângulos absolutos pode sofrer pequenos desvios de subpixel.
2. **Ciclo de Vida de Processos WSL com Encerramento Forçado**:
   - Se o processo host for finalizado abruptamente via Task Manager, janelas WSLg desconectadas podem persistir abertas no compositor do WSLg até o timeout do daemon.
3. **Modo Sandbox no WebView2**:
   - Necessidade de flags específicas ao carregar origens externas não homologadas no catálogo de origens confiáveis (`CloudOsOrigins.cs`).

---

## 8. Próximos Passos Recomendados
1. Finalizar a validação multi-monitor do `NativeWindowManager` para janelas Wayland de alta taxa de quadros.
2. Expandir a suíte de testes de integração do `nativeWindowContract` com cenários de falha de comunicação IPC.
3. Implementar empacotamento MSIX / InnoSetup automatizado via pipeline CI conforme `WINDOWS-PACKAGING-PLAN.md`.
