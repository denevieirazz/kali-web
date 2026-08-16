# CloudOS — estado técnico consolidado

Atualizado em 2026-08-16 para o Stabilization Batch 1.

## Fonte oficial

- Linha oficial: `integration/cloudos-validated-features`
- SHA oficial: `2d3380ba562d23e05947f81cc9581e8fe9bcfdbc`
- Branch de estabilização: `stabilization/cloudos-foundation-batch-1`
- Política: a estabilização parte da linha oficial, não modifica `main`, não promove e não faz merge automaticamente.

## Estado por frente

| Frente | Branch de evidência | Implementado | Compilado/testado | Windows físico | WSL físico | Visual | Promovido | Próximo gate |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Linha oficial / Terminal WSL Core v2 | `integration/cloudos-validated-features@2d3380ba...` | sim | sim | parcialmente validado antes deste lote | sim para a fundação já promovida | não para o crash atual | sim | corrigir lifecycle visual do xterm sem alterar protocolo |
| Files transacional | `feature/cloudos-files-real-transactional@d213dd10...` | sim | CI verde na branch candidata | não | não | não | não | transportar foundation auditada para a estabilização e validar os 3 providers |
| Onboarding + UX Files | `feature/cloudos-onboarding-files-ux@e034e4be...` | sim | CI verde na branch candidata | não | n/a | Playwright automatizado; revisão humana pendente | não | transportar UX necessária, unir com Files transacional e revisar fisicamente |
| Browser físico candidato | `fix/native-browser-physical-ui@710a5da6...` | candidato | evidência própria na branch | candidato separado | n/a | candidato separado | não | não promover neste lote; apenas corrigir capability UX dos modos sem Host |
| System Center Linux | `feature/cloudos-linux-system-center-cgroups@14e125d7...` | sim | CI verde na branch | falha física anterior; correção ainda não aprovada | backend/core saudáveis na evidência anterior | não | não | manter isolado e retomar após estabilização base |

## Problemas confirmados que bloqueiam a estabilização

1. Terminal visual pode lançar `Cannot read properties of undefined (reading 'dimensions')` durante `Terminal.open`/renderer/viewport/resize.
2. Em sessão sem Native Host, o Browser aparece como utilizável e termina em `NATIVE_HOST_UNAVAILABLE` com retry enganoso.
3. Files está dividido entre OPFS oficial, foundation transacional com Windows/WSL e UX visual em outra branch.
4. O fluxo de recovery é tecnicamente seguro, mas precisa linguagem e ações compreensíveis para usuário leigo.
5. O bootstrap depende de comandos/launchers distintos e falhas de processo podem ser escondidas por timeout sem stdout/stderr persistente.
6. Não havia uma fonte única de verdade consumível por humanos e scripts.

## Mapa funcional recomendado nesta branch

| Aplicativo | Frontend | Estado/Modelo | Backend | Nativo | WSL | Testes | Launcher |
|---|---|---|---|---|---|---|---|
| CloudOS Terminal | `frontend/src/apps/CloudOSTerminal` | `terminalWorkspaceState` + transport | `/ws/terminal` | Host somente como shell privilegiado | WSL Core v2 | frontend/backend/probes | launcher unificado |
| CloudOS Browser | `frontend/src/apps/Browser` (launcher) | `browserLauncherState` | nenhum REST de browser | `CloudOS.Host/Browser` | não | Host/Playwright/contract | Full/BrowserValidation |
| CloudOS Files | `frontend/src/apps/CloudOSFiles` | facade por provider + policy visual | `/api/files/*` quando WSL | File System Access API por grant explícito | WSL Core Files | OPFS + Windows + Linux + confinement | FilesValidation |
| System Center | `frontend/src/apps/TaskManager` | virtual na oficial; Linux em branch isolada | `/api/system/*` | métricas host | branch isolada | regressão oficial + branch isolada | não incorporado neste lote |
| Onboarding/Auth | Setup + LockScreen | `accountContract` | `/api/auth/*` | recovery bridge legado quando aplicável | não | backend/frontend/Playwright | UXValidation |

## Launcher correto

A estabilização deve expor `Iniciar CloudOS.cmd`, `Diagnosticar CloudOS.cmd`, `Parar CloudOS.cmd` e `Validar CloudOS.cmd`, todos delegando para scripts versionados em `scripts/launch`, `scripts/diagnostics` ou `scripts/validate`. Enquanto o lote não estiver fisicamente aprovado, essa branch é candidata e não substitui a linha oficial.

## Regra de validação

`implementado`, `compilado`, `testado`, `validado no Windows`, `validado no WSL`, `validado visualmente` e `promovido` são estados independentes. CI não equivale a validação física ou visual.
