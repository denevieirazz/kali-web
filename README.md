# 🛡️ CloudOS - Kali Linux Web Interface

**CloudOS** é um sistema operacional web minimalista que fornece uma interface gráfica no navegador conectada diretamente a um container isolado do **Kali Linux** rodando via Docker no backend.

---

## 🤖 Guia para IAs e Desenvolvedores (Contexto & Arquitetura)

Se você é um agente de IA ou desenvolvedor trabalhando neste repositório, consulte esta seção para entender a arquitetura completa e o estado do sistema.

### 🏗️ Arquitetura do Sistema
```
┌────────────────────────────────┐         WebSocket (ws://)         ┌──────────────────────────────────────┐
│  cloudos-frontend (React/Vite) │ ─────────────────────────────────> │   cloudos-backend (Node.js/Express)  │
│  Porta: 5173                   │                                   │   Porta: 8080                        │
└────────────────────────────────┘                                   └──────────────────┬───────────────────┘
                                                                                        │ Dockerode Socket
                                                                                        ▼
                                                                     ┌──────────────────────────────────────┐
                                                                     │     Docker Desktop (Windows Engine)  │
                                                                     │  Container: kalilinux/kali-rolling   │
                                                                     └──────────────────────────────────────┘
```

### 📁 Estrutura de Arquivos
- **`cloudos-backend/`**: Servidor Node.js
  - `server.js`: Servidor Express + WebSocketServer (`ws`). Conecta ao Docker Windows Named Pipe (`\\.\pipe\docker_engine`), cria um volume persistente por usuário (`kali_hd_{userId}`) e executa uma sessão bash interativa da imagem `kalilinux/kali-rolling`.
- **`cloudos-frontend/`**: Aplicação Web React (Vite)
  - Interface desktop web simulando o CloudOS, comunicando via WebSocket com o backend na porta `8080`.
- **`iniciar-cloudos.vbs`**: Script VBScript que inicializa backend e frontend **100% em segundo plano** (sem janelas de terminal visíveis).
- **`iniciar-cloudos.bat`**: Atalho executável de um clique que invoca o `iniciar-cloudos.vbs` e abre `http://localhost:5173`.
- **`.agents/AGENTS.md`**: Regras de autonomia total para agentes de IA pair programming.

---

## 📋 Pré-requisitos

Para rodar o projeto localmente, a máquina Windows precisa ter:

1. **WSL 2 (Windows Subsystem for Linux)**
   - Necessário para o Docker Desktop rodar contêineres Linux.
   - Para instalar, abra o PowerShell como Administrador e execute:
     ```powershell
     wsl --install
     ```
   - Reinicie o computador após a instalação.

2. **Docker Desktop**
   - Baixe e instale o [Docker Desktop para Windows](https://www.docker.com/products/docker-desktop/).
   - Certifique-se de que o Docker Desktop está aberto e rodando.

3. **Node.js (v18+)**
   - Baixe e instale o [Node.js](https://nodejs.org/).

---

## 🚀 Como Executar

### Opção 1: Execução Automática (Sem Janelas de Terminal)
Basta dar **duplo clique** no arquivo:
👉 `iniciar-cloudos.bat`

Isso iniciará o Backend e Frontend em segundo plano e abrirá automaticamente o navegador em `http://localhost:5173`.

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

## 🛠️ Alterações e Melhorias Realizadas

1. **Correção do Docker no Windows**: Configurado a comunicação do `dockerode` com o Socket Pipe do Windows (`\\.\pipe\docker_engine`).
2. **Inicialização Silenciosa**: Criado o script `iniciar-cloudos.vbs` utilizando `WScript.Shell` para ocultar totalmente os terminais ao iniciar o projeto.
3. **Persistência de Dados**: Cada container cria/monta um volume virtual (`kali_hd_{userId}`) para salvar os arquivos do usuário no diretório `/root`.
4. **Configuração para IAs**: Adicionado diretório `.agents/` com instruções de execução autônoma.

---

## 📜 Licença
Este projeto é de uso livre para fins educacionais e de estudo.
