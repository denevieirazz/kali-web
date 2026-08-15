# CloudOS Core Hardening

Este documento define a direção de decomposição do núcleo do CloudOS sem recomeçar o projeto e sem quebrar compatibilidade com o filesystem/registro já persistidos.

## Objetivos

1. manter `CloudOS.Host`, Browser nativo, autenticação, OPFS e WSL funcionando durante a refatoração;
2. remover responsabilidades de infraestrutura de componentes React;
3. impedir timers, filas e foco inválido de sobreviverem a reset/crash;
4. reduzir renders globais e trabalho repetido no shell;
5. transformar layout e políticas em funções puras testáveis;
6. consolidar estilo, acessibilidade e diagnóstico;
7. extrair gradualmente o kernel monolítico em managers especializados.

## Kernel facade

`frontend/src/core/kernel.ts` passa a ser o ponto público estável. A implementação histórica foi movida sem alteração de bytes para `kernelLegacy.ts` e continua fornecendo compatibilidade completa.

`kernelHardening.ts` é a fronteira transitória única. Ele instala correções idempotentes enquanto as responsabilidades são extraídas para módulos próprios. Nenhum componente React deve acessar `_user`, `_resources`, `_windows`, `_runQueues` ou qualquer outro campo privado diretamente.

### Correções instaladas

- janelas `Desktop` e `Taskbar` nunca podem ser a janela ativa do usuário;
- foco é reconciliado após abrir/fechar/minimizar/restaurar janelas e finalizar processos;
- `focusWindow` ignora IDs inexistentes e superfícies de sistema;
- reset encerra scheduler, uptime e resource loop antes de reinicializar;
- filas do scheduler são limpas antes da recriação dos processos-base;
- BSOD encerra também o resource loop;
- múltiplos uptime counters não podem acumular;
- alocações de memória inválidas são rejeitadas;
- alteração de memória de processo atualiza a contabilização global;
- RAM fixa adicionada por `loadShell()` deixa de ser contada duas vezes;
- sincronização de usuário e RAM física fica encapsulada em `kernelAdmin`.

## Shell React

`App.tsx` é apenas composition root. Handshake nativo, sincronização do kernel, BSOD, watchdogs, hotkey global, viewport e layout das superfícies do sistema vivem em `hooks/useCloudOSRuntime.ts`.

Seletores Zustand são granulares. Em especial, os ticks de CPU/processos não devem provocar rerender do `App` inteiro quando o PID do Explorer não mudou.

Resize do viewport é agrupado por `requestAnimationFrame` e a geometria fica em `core/shellLayout.js`, com testes Node puros.

## Rendering

`WindowRenderer` mantém cada aplicação lazy dentro de um componente memoizado. Alterações em uma janela continuam chegando pelo próprio `Window`, mas não obrigam todos os aplicativos irmãos a rerender apenas porque o array global de janelas recebeu um novo snapshot.

A carga lazy agora possui feedback visual e acessível, em vez de uma região vazia.

## Rede/API

O `apiClient` continua sendo a única camada HTTP do frontend. Ele agora:

- mantém timeout interno;
- respeita `AbortSignal` fornecido pelo chamador;
- diferencia cancelamento de timeout;
- remove listeners sempre em `finally`;
- usa `Headers` em vez de cast inseguro;
- não adiciona `Content-Type` JSON quando não há body;
- mantém sanitização do perfil persistido.

## Design system

A baseline visual escura permanece deliberadamente compatível com os snapshots Playwright existentes. A camada aditiva `cloudosEnhancements.css` acrescenta tema claro, seleção de texto, reduced motion e loading state sem alterar a geometria padrão durante esta refatoração.

A importação legada de Google Fonts continua temporariamente em `index.css`. Ela não será removida por relaxamento de CSP nem por atualização cega dos snapshots; a troca para uma pilha local deve acontecer numa migração visual dedicada, com comparação e aprovação dos novos baselines.

## Diagnóstico

Environment Doctor foi promovido para Saúde do Sistema e verifica OPFS, backend, runtime, WebSocket, Host nativo, Explorer/DWM, user32/gdi32, drivers e serviços, além de CPU, RAM, processos e uptime.

O reparo oferecido nessa tela atua somente no filesystem virtual protegido do CloudOS; não executa reparos destrutivos no Windows/WSL.

## Próximas extrações

O arquivo `kernelLegacy.ts` ainda é grande. A migração deve ocorrer sem big-bang, nesta ordem:

1. `WindowManagerCore` — tabela, foco, snapping e work area;
2. `ProcessManagerCore` — PID, lifecycle, sinais e worker ownership;
3. `ResourceManager` — RAM/CPU/uptime e budgets;
4. `ServiceManager` — serviços, dependências e restart policy;
5. `VirtualFileSystem` — operações atômicas, move/rename de árvores e migrations;
6. `RegistryManager` — schema/versionamento/migrations;
7. `ExecutionEngine` — OSL, workers e syscalls;
8. `SessionManager` — usuário, lock/login e startup apps.

Depois dessa base, as features de produto podem crescer sem duplicar infraestrutura: Terminal Workspace, File Preview, Settings completo, Package/App Platform e Kali Tool Center.

## Regras

- não reduzir quantidade de arquivos juntando responsabilidades;
- reduzir duplicação e tamanho de módulos por extração coerente;
- todo bug corrigido ganha teste ou contrato automatizado;
- nenhum app externo recebe bridge/tokens privilegiados;
- nenhuma mudança desta fase altera banco real, OPFS do usuário ou WSL de forma destrutiva;
- `main` só recebe mudanças por integração explícita posterior.
