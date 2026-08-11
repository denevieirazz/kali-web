# Plano de Empacotamento para Windows — CloudOS-Unified

## 1. Visão Geral
Este documento estabelece o plano arquitetural para empacotar o **CloudOS-Unified** em um aplicativo desktop executável nativo do Windows (arquivo `.exe` / instalador `.msi` via Electron / NSIS), sem a necessidade de instalar o WSL automaticamente durante a instalação do software base.

---

## 2. Componentes da Arquitetura Desktop (Electron + Node.js Integrado)

```
[ Instalador CloudOS-Setup.exe (NSIS) ]
          │
          ├──> Instala em: %LOCALAPPDATA%\Programs\CloudOS-Unified\
          ├──> Dados em:   %APPDATA%\CloudOS-Unified\
          │
          ├──> Inicia o Processo Desktop Host (Electron ElectronMain.js)
          │       ├── Backend Node.js em background (PID isolado em 127.0.0.1)
          │       └── Janela Principal Glassmorphism (Chromium Window)
          │
          └──> Atalho na Área de Trabalho e Menu Iniciar
```

---

## 3. Estrutura do Instalador (NSIS / Electron Builder)

### A. Diretório de Instalação e Dados
- **Binários e Código**: `%LOCALAPPDATA%\Programs\CloudOS-Unified\`
- **Preservação de Dados do Usuário**: `%APPDATA%\CloudOS-Unified\`
  - `runtime/backend-port.json`
  - `database/cloudos.db` (banco de dados SQLite local)
  - `user-preferences.json`

### B. Inicialização Oculta do Backend
- O processo backend será iniciado como um worker filho desanexado (`child_process.spawn`) pelo processo principal do Electron.
- Nenhuma janela de console CMD ou terminal PowerShell será visível ao usuário durante a execução normal.

### C. Atalhos no Sistema
- **Área de Trabalho**: `CloudOS Unified.lnk` com ícone personalizado `.ico`.
- **Menu Iniciar**: `CloudOS Unified` em `Programs\CloudOS Unified`.

### D. Desinstalador Limpo (Uninstaller)
- O desinstalador NSIS removerá apenas os executáveis em `%LOCALAPPDATA%\Programs\CloudOS-Unified\`.
- **Preservação de Dados**: Pergunta ao usuário se deseja manter a pasta de dados `%APPDATA%\CloudOS-Unified\` para evitar perda acidental de configurações e arquivos virtuais.

---

## 4. Detecção Prévia de Pré-requisitos (Runtime Inspector)

Antes da execução dos serviços, o verificador interno valida:
1. **Node.js**: Detectado no pacote empacotado (Node runtime embutido no Electron).
2. **Portas Dinâmicas**: Bind nativo em `127.0.0.1` entre portas 18080-18180 para backend e 15173-15200 para frontend.
3. **Detecção do WSL**: Consulta não-destrutiva via `wsl.exe --list --verbose` para vincular o shell Linux caso a distribuição `kali-linux` esteja presente.

---

## 5. Próximos Passos na Fase de Build Nativo
1. Configuração do `electron-builder.json`.
2. Criação do script de empacotamento `npm run package:win`.
3. Geração do instalador único `CloudOS-Unified-Setup-1.0.0.exe`.
