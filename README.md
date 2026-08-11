# CloudOS Unified — Web Operating System

CloudOS Unified é um sistema operacional web empresarial e moderno executado diretamente no navegador, combinando uma interface fluida com design **Glassmorphism (UI Nativa 02.1)**, persistência via **OPFS (Origin Private File System)**, terminal integrado com suporte a sessões interativas no **WSL (Windows Subsystem for Linux)** e arquitetura de microsserviços segura em **Node.js**.

---

## 🚀 Arquitetura Geral

```
┌─────────────────────────────────────────────────────────────┐
│                    CloudOS Web (Frontend)                   │
│  - React 19 + TypeScript + Vite + Zustand                   │
│  - Design System Glassmorphism (Acrílico & Blur)           │
│  - Menu Iniciar Nativo (Início / Todos / Abertos)           │
│  - OPFS Storage Explorer (Arquivos Locais + Lixeira)        │
│  - Gerenciador de Janelas, Processos & Menu de Contexto     │
└──────────────┬───────────────────────────────▲──────────────┘
               │ HTTP / JSON API               │ WebSocket PTY
               ▼                               │
┌──────────────────────────────────────────────┴──────────────┐
│                  CloudOS Backend (Node.js)                  │
│  - Express + Helmet + CORS restrito a 127.0.0.1             │
│  - Autenticação JWT com segredo rotativo dinâmico           │
│  - Banco de Dados JSON Atômico e Persistente                │
│  - Terminal PTY Seguro (execução isolada via array spawn)   │
│  - Diagnóstico e Integração com Distribuições WSL (Kali)    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Funcionalidades Principais

1. **Autenticação & Primeiro Acesso**:
   - Tela de Primeiro Acesso em Glassmorphism violeta/azul.
   - Criação de usuário administrador local com hashing bcrypt.
   - Nenhuma credencial padrão ou senha estática pré-definida.
   - Sessões seguras assinadas via JWT.

2. **Gerenciamento de Arquivos com OPFS**:
   - Armazenamento 100% no navegador via Origin Private File System (`navigator.storage.getDirectory()`).
   - Criação, renomeação recursiva, exclusão segura e restauração via Lixeira (`.trash/`).
   - Edição de texto integrada, upload/download e estimativa de quota de armazenamento.

3. **Menu de Contexto Acessível**:
   - Renderização via React Portal em `document.body`.
   - Ponte de hover com tolerância temporal (`HOVER_DELAY_MS`) para transição de submenus sem fechamento acidental.
   - Posicionamento inteligente com cálculo de flip e shift contra as bordas da tela.
   - Navegação completa por teclado (`ArrowDown`, `ArrowUp`, `ArrowRight`, `ArrowLeft`, `Home`, `End`, `Enter`, `Escape`).

4. **Terminal Web com Integração WSL**:
   - Conexão WebSocket bidirecional autenticada via token JWT.
   - Detecção automática de instâncias WSL locais (`kali-linux` preferencial).
   - Execução com passagem de argumentos em array (`execFileSync`), sem concatenação em shell.

5. **Navegador CloudOS Dual-Mode**:
   - **Modo Interno**: Iframe seguro para origens compatíveis (Wikipedia, DuckDuckGo, OpenStreetMap).
   - **Modo Externo / Fallback Seguro**: Cartão de aviso e botão destacado para abertura no navegador nativo para sites com cabeçalho `X-Frame-Options` ou `SAMEORIGIN`.

---

## 🛠️ Requisitos e Instalação

- **Node.js**: v18+ (recomendado Node.js v22 LTS)
- **Sistema Operacional**: Windows 10/11 ou Linux/macOS (para a versão Web)

### Instalação de Dependências

```bash
# Na raiz do repositório
npm install
```

---

## 💻 Execução Local

```bash
# Iniciar frontend e backend simultaneamente em modo desenvolvimento
powershell.exe -ExecutionPolicy Bypass -File scripts/start-dev.ps1

# Ou iniciar manualmente:
npm --prefix backend start
npm --prefix frontend run dev
```

- **Frontend**: `http://127.0.0.1:15173`
- **Backend API**: `http://127.0.0.1:18080` (porta dinâmica com bind exclusivo em `127.0.0.1`)

---

## 🧪 Suíte de Testes e Validação

```bash
# Validação de lint (TypeScript e JavaScript)
npm run lint

# Build de produção do frontend
npm run build

# Testes de unidade e persistência do backend
npm test

# Testes ponta-a-ponta (E2E) e de estabilidade
npm run test:e2e
```

---

## 🔒 Variáveis de Ambiente (`.env.example`)

Copie `backend/.env.example` para `backend/.env` se desejar configurar portas e diretórios customizados:

```env
PORT=18080
HOST=127.0.0.1
CORS_ORIGIN=http://127.0.0.1:15173,http://localhost:15173
JWT_EXPIRES_IN=2h
```

*(Caso `JWT_SECRET` não seja fornecido, o backend gera automaticamente um segredo criptográfico aleatório de 64 caracteres hexadecimais no primeiro boot).*

---

## 📄 Política de Segurança

Para relatar vulnerabilidades de segurança de maneira responsável, consulte o arquivo [SECURITY.md](SECURITY.md).
