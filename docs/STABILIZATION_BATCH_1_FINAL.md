# CloudOS Stabilization Batch 1 — fechamento técnico

## Escopo

Branch exclusiva do lote: `stabilization/cloudos-foundation-batch-1`.

Base imutável comprovada pelo lote: `integration/cloudos-validated-features` em `2d3380ba562d23e05947f81cc9581e8fe9bcfdbc`.

Este fechamento não faz merge, promoção, rebase, force-push, reset destrutivo nem altera `main`.

## O que o fechamento adiciona

- entrada física única `Validar CloudOS.cmd`;
- orquestrador físico `scripts/validate/run-stabilization-batch1.ps1`;
- contrato explícito de safety boundary;
- estrutura canônica e índice central de `test-results`;
- CI dedicado ao lote com Linux e Windows;
- regressão completa no Windows CI e core Linux no Linux CI.

## Safety boundary

O validador físico usa exclusivamente `test-results/.../isolated-data` por meio de `CLOUDOS_DATA_DIR`, `CLOUDOS_TEST_ROOT` e `DATABASE_PATH`. O banco real não faz parte do fluxo de validação.

O validador não executa comandos WSL mutantes. Os únicos comandos WSL próprios do fechamento são snapshots read-only de estado para evidência antes/depois.

O teardown do launcher continua restrito aos PIDs gravados pela sessão e confirma a identidade do processo pelo `StartTime`; não existe kill amplo por nome.

Git destrutivo é proibido pelo contrato do fechamento.

## Evidências automatizadas esperadas

A regressão cobre, sem declarar aprovação visual:

- lifecycle de geometria/fit/teardown do Terminal;
- capability UX do Browser em modos sem Native Host;
- contratos e smoke do Browser nativo no runner Windows descartável;
- Files unificado com OPFS, Windows grant e Linux Home;
- onboarding/recovery;
- launcher, logs e isolamento de dados;
- backend, integração, frontend, E2E e Playwright;
- Host/Bootstrap/Browser/.NET;
- WSL core por contratos Windows e testes/build Go no Linux.

O smoke nativo existente também exige que fechar a BrowserWindow não encerre Shell/backend e que descendentes pertencentes ao Host desapareçam após o encerramento.

## Aprovação

O CI pode provar compilação, testes e contratos automatizados. Ele não concede validação no Windows físico do usuário, no WSL2 físico nem validação visual.

Essas três aprovações permanecem explicitamente externas e pertencem a Gemini Low, usuário e Copilot principal.
