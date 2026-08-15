# CloudOS Terminal Workspace

Branch: `feature/cloudos-terminal-workspace`

Esta feature transforma o Terminal CloudOS de uma única sessão descartável em um workspace multi-sessão sem alterar a fronteira de segurança do backend.

## Garantias

- cada aba abre seu próprio WebSocket autenticado e, consequentemente, seu próprio PTY isolado no backend;
- perfis continuam limitados aos valores aceitos pelo servidor (`powershell` e `wsl`);
- a distribuição WSL continua validada pelo backend; o frontend não envia executável, shell, argv ou comando de inicialização arbitrário;
- no máximo 8 sessões são mantidas simultaneamente pelo workspace;
- fechar uma aba envia `close`, fecha o WebSocket, remove handlers/ResizeObserver e destrói o xterm;
- abas ocultas permanecem vivas e não perdem a sessão; ao voltar ao layout visível recebem `fit()` novamente;
- split usa duas sessões reais, não duplica DOM/output de uma sessão;
- nenhuma senha, JWT, comando, output, cwd ou histórico de terminal é persistido pelo workspace.

## Persistência

Somente estes campos podem ir para `localStorage` em `cloudos_terminal_workspace_v1`:

```json
{
  "tabs": [
    { "id": "...", "profile": "powershell", "distribution": "" },
    { "id": "...", "profile": "wsl", "distribution": "kali-linux" }
  ],
  "activeId": "...",
  "splitId": null
}
```

Dados extras presentes em um payload antigo/corrompido são descartados durante normalização.

## UX

- abas PowerShell/WSL;
- escolha de distribuição para a aba ativa;
- status individual por sessão;
- reconexão individual;
- split de duas sessões;
- restore do workspace quando o Terminal é aberto sem parâmetros explícitos;
- fallback automático para PowerShell quando WSL não está disponível;
- limite visual de sessões;
- layout responsivo.

### Atalhos

- `Ctrl+Shift+T`: nova aba usando o perfil atual;
- `Ctrl+Shift+W`: fecha a aba ativa;
- `Ctrl+PageDown`: próxima aba;
- `Ctrl+PageUp`: aba anterior;
- `Alt+Shift+D`: alterna split.

## Testes

`frontend/test/terminalWorkspaceState.test.js` cobre normalização, remoção de campos arbitrários, add/activate/cycle/close, fallback da última aba, split, limite de PTYs e troca segura WSL → PowerShell.

A CI desta branch roda lint, build, backend/integration, E2E, frontend unit, Host build/tests e `git diff --check` contra `integration/cloudos-foundation`.
