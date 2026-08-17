# CloudOS Release Candidate Audit

Escopo: foundation e productization da branch `productization/cloudos-distribution-batch-2`. Este documento não promove, não publica release e não substitui o gate físico.

## CONFIRMADO NO CÓDIGO

- O produto permanece em `development` / `unsigned-development`, com publicação stable desabilitada.
- O launcher de desenvolvimento possui os modos reais `Web` e `Full`. Neste relatório, `WebOnly` é apenas o nome de auditoria para `-Mode Web`; não existe um terceiro modo implícito.
- `Full` delega ao launcher nativo existente; nenhuma nova superfície de produto foi adicionada no RC.
- O shutdown agora observa somente processos CloudOS conhecidos, solicita encerramento de UI quando disponível e falha se os processos capturados não desaparecerem dentro do limite. Não há force-kill.
- Updater, rollback, backup, restore, installer, portable, diagnostics e supply chain continuam nas implementações já existentes e passam pelos gates de productization.
- O runtime distribuído leva `runtime/node.exe` e `runtime/cloudos-core`; Node/Go globais são toolchain de build, não dependências ocultas do runtime distribuído.
- `manifest.json` de staging e `portable-manifest.json` não são redundantes: descrevem layouts diferentes. O mesmo vale para os checksums de staging e portable.
- `docs/DISTRIBUTION.md` e `docs/DISTRIBUTION_AUDIT.md` têm papéis distintos: operação/distribuição versus política/evidência de auditoria.
- Os workflows existentes foram mantidos quando o gatilho/objetivo é distinto; repetição de regressões entre linhas de estabilização e productization não foi tratada como duplicação funcional.
- Os utilitários one-off `Reverter-Ultima-Correcao-Core-UI.ps1/.cmd` foram classificados como obsoletos: dependiam de `backup-core-ui-*`, não há backup correspondente no estado RC e não há referência operacional ativa.

## CONFIRMADO EM TESTES

- Contratos de branch/base, canais, artifact policy, diagnóstico, supply chain, updater, rollback, backup/restore, recovery, installer, portable e proteção do banco permanecem automatizados.
- O gate RC verifica headings deste relatório, caminhos de scripts referenciados pelos workflows, ausência dos rollback scripts obsoletos e preservação de `validation.json` como `not-run`.
- O gate de órfãos verifica que não restem `CloudOS.Host.exe`, `CloudOS.Bootstrap.exe`, `CloudOS.WslCore.exe` nem backend Node identificável após a sequência automatizada do Windows.
- O hardening do instalador continua provando ausência de dependência de Node global e Go global no produto distribuído.

## CONFIRMADO EM CI

- A baseline anterior da mesma branch fechou Linux e Windows em verde na HEAD `811d5e41e403ecaf31a452648bccf13fd5d32241`.
- A execução RC final deverá repetir Linux e Windows completos. Os números de tamanho serão gravados em `artifacts/audit/release-candidate-metrics.json` e só serão transcritos aqui depois de uma medição real da HEAD RC.

### Métricas RC

- Startup WebOnly (`-Mode Web`): **não medido**. O launcher atual retorna após o spawn do servidor de desenvolvimento e não expõe um sinal de readiness; medir apenas o spawn seria enganoso.
- Startup Full: **não medido** em CI hospedada. O caminho é nativo/interativo e não será usado como substituto de gate físico/visual.
- Shutdown: **não medido** em CI hospedada enquanto não houver um ciclo completo e representativo de startup Full seguido de shutdown.
- Memória dos principais componentes: **não medida** em CI hospedada; processos transitórios de build/teste não representam consumo de runtime.
- Instalador: **aguardando medição da CI RC**.
- Portátil: **aguardando medição da CI RC**.
- Update full/delta: **aguardando medição da CI RC**.
- Diagnósticos: **aguardando medição da CI RC**.

## CONFIRMADO EM VALIDAÇÃO FÍSICA

Nenhum item. O gate físico não foi executado e `productization/validation.json` deve permanecer com `status=not-run` e `visualValidation=not-run` até a execução explícita em máquina física.

## NÃO CONFIRMADO

- Tempo de startup WebOnly até readiness real.
- Tempo de startup Full até janela utilizável.
- Tempo de shutdown de um ciclo Full real.
- Consumo de memória representativo de Host, Bootstrap, backend e WSL core em uma sessão física.
- Comportamento visual do instalador, shortcuts, janela Host e fluxos de usuário em máquina física.
- Smoke real do WSL core quando não existe distro no runner hospedado.
- Assinatura Authenticode e cadeia de confiança de produção.

## RISCOS

- O candidato continua `unsigned-development`; não é apropriado para promoção/distribuição final.
- A CI hospedada não substitui validação física/visual, principalmente para WSL, WebView2, atalhos e lifecycle de janelas/processos.
- O launcher Web de desenvolvimento depende da toolchain de desenvolvimento e não possui readiness explícito; isso impede uma métrica de startup honesta no RC automatizado.
- O shutdown de processos sem janela não possui um canal dedicado de encerramento; o script RC falha fechado em vez de matar processos à força.

## DÍVIDAS TÉCNICAS

- Vite ainda reporta chunk principal acima de 500 kB e sobreposição de import dinâmico/estático em `appRegistry.ts`; não é bloqueio de productization e não será aberto como frente no RC.
- GitHub Actions avisa sobre actions que ainda declaram Node 20 e são forçadas pelo runner para Node 24; o runtime do produto continua pinado separadamente.
- `actions/setup-go` pode avisar que não encontra `go.sum` na raiz porque o módulo Go é aninhado; build/teste do módulo continuam explícitos.
- Há repetição deliberada de regressões entre workflows de linhas diferentes. Consolidar workflows é trabalho pós-RC somente se preservar gates/branch scopes sem reduzir evidência.
- Um canal de shutdown explícito para componentes sem janela pode ser avaliado pós-RC; no RC o comportamento é fail-closed.

## PÓS-RC

1. Executar o gate físico preparado, sem ajustes manuais nos artefatos.
2. Registrar `validation.json`, screenshots, logs, banco/WSL/processos antes e depois.
3. Medir startup Full/WebOnly, shutdown e memória em ambiente representativo apenas se o validador físico passar a capturar readiness/lifecycle de forma objetiva.
4. Tratar assinatura/certificado e decisão de promoção em etapa separada.
5. Somente após evidência física/visual satisfatória discutir promoção ou distribuição.
