# CloudOS — Matriz de Testes

## Baseline geral

| Área | Comando | Ambiente | Gate |
|---|---|---|---|
| PowerShell runtime guard | `./scripts/test-powershell7-requirement.ps1` | Windows / PowerShell 7.2+ + Windows PowerShell 5.1 instalado | obrigatório |
| Lint | `npm.cmd run lint` | Windows/Node 22 | obrigatório |
| Frontend build | `npm.cmd run build` | Windows/Node 22 | obrigatório |
| Backend | `npm.cmd test` | Windows/Node 22 | obrigatório |
| E2E Node | `npm.cmd run test:e2e` | Windows/Node 22 | obrigatório |
| Frontend unit | `node scripts/run-node-tests.js frontend/test` | Windows/Node 22 | obrigatório |
| Host build | `dotnet build desktop/CloudOS.Host/CloudOS.Host.csproj -c Release` | Windows/.NET 8 | obrigatório |
| Host tests | `dotnet run --project desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj -c Release` | Windows/.NET 8 | obrigatório |
| Bootstrap build/tests | build + run dos projetos Bootstrap | Windows/.NET 8 | obrigatório |
| Playwright legado | `npx playwright test --grep-invert "Navegador CloudOS — WebView2 real"` | Windows | obrigatório |

## Navegador Nativo

| Cenário | Camada | Resultado esperado |
|---|---|---|
| domínio sem esquema | Host unit | HTTPS |
| localhost/IPv4/IPv6 loopback | Host unit | HTTP |
| IDN | Host unit | normalização segura/punycode |
| userinfo/CR/LF/NUL/URL grande | Host unit | bloqueado |
| schemes perigosos/desconhecidos | Host unit | bloqueado |
| `cloudos.local` | Host unit + WebView2 | bloqueado |
| backend efêmero e aliases | Host unit + WebView2 | HTTP(S) bloqueado |
| WebSocket do terminal | backend unit + WebView2 | origem externa rejeitada; JWT continua obrigatório |
| X-Frame-Options DENY | WebView2 real | carrega top-level |
| CSP `frame-ancestors 'none'` | WebView2 real | carrega top-level |
| bridge/nonce/runtime | WebView2 real | ausentes no site externo |
| popup | WebView2 real | nova aba, sem Edge externo |
| cookies entre abas Browser | WebView2 real | compartilhados no profile Browser |
| file:// | WebView2 real | bloqueado |
| redirect para shell/backend | WebView2 real | bloqueado antes de atingir alvo interno |
| permissões não allowlisted | Host unit | deny |
| origem muda durante prompt | Host unit + manual | deny |
| TLS inválido | Host unit + manual | `Cancel`, sem bypass |
| dois downloads | WebView2 real | ambos acompanhados e canceláveis em lote |
| fechar com download | WebView2 real | download cancelado no shutdown |
| renderer crash | Host unit + WebView2 real | primeira recuperação; segunda em ≤30 s para loop |
| Dispose | revisão + lifecycle WebView2 | handlers removidos e controle descartado uma vez |
| estado corrompido | Host unit | quarentena/fallback sem criar dados sensíveis |
| sessão opcional | Host unit + manual | restaura URLs sanitizadas/pins somente |
| duas `browser.open` simultâneas | Host smoke | uma janela criada e a segunda chamada reutiliza |
| fechar Browser | Host smoke | Shell e `/api/health` continuam ativos |
| fechar Host | Host smoke | Browser/backend/filhos encerrados |
| validador em Windows PowerShell 5.1 | runtime guard | falha imediata com `POWERSHELL_7_REQUIRED` antes de acessar `$IsWindows` |
| smoke em Windows PowerShell 5.1 | runtime guard | falha imediata com `POWERSHELL_7_REQUIRED` antes das APIs modernas |

### Validação Windows local oficial

O validador completo e o smoke nativo exigem **PowerShell 7.2 ou superior (`pwsh.exe`)**. Windows PowerShell 5.1 (`powershell.exe`) não é um runtime suportado para esses scripts; a tentativa deve falhar imediatamente com `POWERSHELL_7_REQUIRED` e informar o runtime detectado.

Comando oficial em Windows Sandbox/VM descartável e limpa:

```powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-native-browser-windows.ps1 -DisposableProfile
```

Depois que o validador já está em PowerShell 7, scripts PowerShell filhos são executados na **mesma sessão**, sem exigir que outro `pwsh` seja localizado no `PATH`.

### Comandos específicos

```powershell
# TestHost e testes WebView2 reais
dotnet build desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj -c Release
npx playwright test tests/playwright/native-browser.spec.ts --output=test-results/native-browser --reporter=list

# Smoke completo — somente CI ou VM/Sandbox descartável, sempre PowerShell 7.2+
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-native-browser-host-smoke.ps1 -AllowNonCi
```

Fora do CI, o smoke exige `-AllowNonCi` e recusa execução quando já existe um perfil `%LOCALAPPDATA%\CloudOS`. Isso evita usar o banco real como fixture.

## Artifacts de falha

A CI da feature publica somente `test-results/native-browser/` quando houver falha. O spec nativo desliga o trace binário do Playwright e produz diagnóstico textual sanitizado e screenshot de falha.

Nunca incluir em artifact:

- `%LOCALAPPDATA%\CloudOS`;
- UDF WebView2;
- banco CloudOS;
- cookies;
- JWT, supervisor/lease tokens;
- senhas/recovery codes;
- dump completo de environment.

## Aprovação

A feature não deve ser considerada pronta para integração enquanto o **HEAD final** não tiver:

1. workflow Windows concluído com sucesso;
2. guard PowerShell 7.2+ validado contra `pwsh` e Windows PowerShell 5.1;
3. Host/TestHost compilados;
4. Host/Bootstrap/backend/frontend verdes;
5. Playwright legado sem regressão;
6. Playwright WebView2 real verde;
7. smoke Host lifecycle verde;
8. `git diff --check` verde;
9. revisão de artifacts/segredos concluída.
