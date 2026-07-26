# 🛡️ CloudOS - Kali Linux Web Interface

**CloudOS** é um sistema operacional web minimalista que fornece uma interface gráfica interativa no navegador conectada diretamente a um container isolado do **Kali Linux** rodando via Docker no backend.

---

## 🤖 Guia Completo para IAs e Desenvolvedores (Contexto & Arquitetura)

Se você é um agente de IA ou desenvolvedor trabalhando neste repositório, consulte esta seção para entender a arquitetura técnica completa, o histórico de correções e o estado do sistema.

### 🏗️ Arquitetura do Sistema
```
┌────────────────────────────────┐         WebSocket (ws://)         ┌──────────────────────────────────────┐
│  cloudos-frontend (React/Vite) │ ─────────────────────────────────> │   cloudos-backend (Node.js/Express)  │
│  Porta: 5173                   │                                   │   Porta: 8080                        │
└────────────────────────────────┘                                   └──────────────────┬───────────────────┘
                                                                                        │ Dockerode Named Pipe
                                                                                        ▼
                                                                     ┌──────────────────────────────────────┐
                                                                     │     Docker Desktop (Windows Engine)  │
                                                                     │  Container: kalilinux/kali-rolling   │
                                                                     └──────────────────────────────────────┘
```

### 📁 Estrutura de Arquivos e Componentes

- **`cloudos-backend/`**: Servidor Node.js
  - `server.js`: Servidor Express + WebSocketServer (`ws`). 
    - Conecta ao Windows Named Pipe do Docker (`\\.\pipe\docker_engine`).
    - Verifica a presença da imagem `kalilinux/kali-rolling:latest` localmente e faz o pull automático via `docker.pull()` se necessário.
    - Cria volumes persistentes por usuário (`kali_hd_{userId}`) montados no diretório `/root`.
    - Transmite buffers de terminal sem quebra de codificação UTF-8 (`stream.on('data')`).
    - Implementa heartbeat de Ping/Pong (30s) para fechar sessões inativas e parar contêineres graciosamente (`container.stop({ t: 2 })`).
- **`cloudos-frontend/`**: Aplicação Web React + Vite
  - `src/main.jsx`: Define o polyfill `window.process` no topo da execução para evitar falhas do `react-rnd` no navegador.
  - `src/apps.jsx`: Renderiza o terminal `xterm.js` com `ws.binaryType = 'arraybuffer'`, suporte a `Uint8Array` e temporizador de 150ms contra o ciclo de montagem dupla do *React 18 Strict Mode*.
  - `src/Window.jsx`: Gerenciador de janelas arrastáveis e maximizáveis baseado em `react-rnd`.
  - `src/App.jsx` & `src/index.css`: Gerenciador de desktop estilo Windows 11 com barra de tarefas, menu iniciar e estilos unificados.
  - `vite.config.js`: Configurado com o bloco `define: { 'process.env': {} }`.
- **`iniciar-cloudos.vbs`**: Script VBScript que inicializa backend e frontend **100% em segundo plano** chamando os executáveis diretos do Node.js.
- **`iniciar-cloudos.bat`**: Atalho executável de um clique para invocar o `iniciar-cloudos.vbs` e abrir `http://localhost:5173`.
- **`.agents/AGENTS.md`**: Regras de autonomia total para agentes de IA pair programming.

---

## 📋 Pré-requisitos do Sistema

Para rodar o projeto no Windows:

1. **WSL 2 (Windows Subsystem for Linux)**
   - Necessário para o suporte a contêineres Linux no Docker Desktop.
   - Para instalar via PowerShell (Administrador):
     ```powershell
     wsl --install
     ```
   - Reinicie o computador após a instalação.

2. **Docker Desktop**
   - Baixe e instale o [Docker Desktop para Windows](https://www.docker.com/products/docker-desktop/).
   - Certifique-se de que o Docker está aberto e rodando (`Engine running`).

3. **Node.js (v18+)**
   - Baixe e instale o [Node.js](https://nodejs.org/).

---

## 🚀 Como Executar

### Opção 1: Execução em 1 Clique (Silenciosa em Segundo Plano)
Basta dar **duplo clique** no arquivo:
👉 `iniciar-cloudos.bat`

Isso iniciará o Backend e o Frontend silenciosamente (sem abrir janelas de terminal pretas) e abrirá automaticamente o navegador em `http://localhost:5173`.

---

### Opção 2: Execução Manual pelo Terminal

#### 1. Iniciar o Backend
```bash
cd cloudos-backend
npm install
node server.js
```
*O backend estará rodando na porta `8080`.*

#### 2. Iniciar o Frontend
Em outro terminal:
```bash
cd cloudos-frontend
npm install
npm run dev
```
*O frontend estará acessível em `http://localhost:5173`.*

---

## 🛠️ Histórico de Alterações e Melhorias Aplicadas

1. **Correção de Conexão com Docker no Windows**: Mapeamento do Named Pipe do Windows (`\\.\pipe\docker_engine`) no `dockerode`.
2. **Download Automático de Imagens Docker**: Verificação proativa de imagens com `docker.getImage()` e pull automático da imagem `kalilinux/kali-rolling:latest`.
3. **Tratamento de Caracteres e Buffers UTF-8**: Envio e leitura de `Buffer` bruto (`ArrayBuffer` / `Uint8Array`) no `xterm.js` para evitar corrupção de caracteres especiais e ANSI colors.
4. **Gerenciamento de Ciclo de Vida e Recursos (Heartbeat)**: Sistema Ping/Pong a cada 30s e encerramento com *graceful shutdown* (`container.stop({ t: 2 })`) para evitar contêineres zumbis de RAM.
5. **Polyfill `process.env` no Vite**: Injeção do `window.process` em `src/main.jsx` e `vite.config.js` resolvendo o erro `ReferenceError: process is not defined` no `react-rnd`.
6. **Proteção contra React 18 Strict Mode**: Adicionado temporizador de 150ms no `src/apps.jsx` garantindo dimensões válidas do elemento de tela antes do `fitAddon.fit()`.
7. **Modo Silencioso em Segundo Plano**: Script `iniciar-cloudos.vbs` com caminhos absolutos (`C:\Program Files\nodejs\node.exe`) ocultando totalmente os processos do terminal.
8. **Regra de Autonomia de IA**: Diretório `.agents/AGENTS.md` instruindo assistentes de IA a realizarem tarefas diretamente sem repassar comandos manuais desnecessários ao usuário.

---

## 📜 Licença
Este projeto é de uso livre para fins educacionais e de estudo.
