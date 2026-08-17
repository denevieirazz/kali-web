# CloudOS Release Candidate Audit

Escopo: foundation e productization da branch `productization/cloudos-distribution-batch-2`. Este documento não promove, não publica release e não substitui o gate físico.

## CONFIRMADO NO CÓDIGO

- O produto permanece em `development` / `unsigned-development`, com publicação stable desabilitada.
- O Bootstrap productizado possui dois caminhos de inicialização já existentes: **Full**, que supervisiona `CloudOS.Host`, e **WebOnly**, escolhido pelo fluxo de pré-requisitos e executado por `RunWebOnlyAsync`/`WebOnlySession`. O RC não criou um terceiro launcher nem uma nova superfície de produto.
- O caminho Full possui handshake de prontidão, período de estabilidade, crash-loop policy e recuperação; o caminho WebOnly inicia a sessão web, abre o navegador e executa `StopAsync` ao encerrar a janela.
- O shutdown do Bootstrap cancela o lifetime e libera a supervisão/instance guard; não foi adicionada política de force-kill.
- Updater exige origem HTTPS, aplica política de canais e mantém `AllowVersionDowngrade = false` no caminho normal.
- Rollback explícito usa apenas versão anterior conhecida e preserva os dados; detalhes técnicos de falha ficam em log em vez de serem necessários na mensagem principal ao usuário.
- Backup, restore, installer, portable, diagnostics e supply chain continuam nas implementações já existentes e passam pelos gates de productization.
- O runtime distribuído leva `runtime/node.exe` e `runtime/cloudos-core`; Node/Go globais são toolchain de build/CI, não dependências ocultas do runtime distribuído.
- `manifest.json` de staging e `portable-manifest.json` não são redundantes: descrevem layouts diferentes. O mesmo vale para os checksums de staging e portable.
- `docs/DISTRIBUTION.md` e `docs/DISTRIBUTION_AUDIT.md` têm papéis distintos: operação/distribuição versus política/evidência de auditoria.
- Os workflows existentes foram mantidos quando o gatilho/objetivo é distinto; repetição de regressões entre linhas de estabilização e productization não foi tratada como duplicação funcional.
- Os utilitários one-off `Reverter-Ultima-Correcao-Core-UI.ps1/.cmd` foram removidos após a auditoria confirmar ausência de backup `backup-core-ui-*` correspondente e ausência de referência operacional ativa.
- As mensagens de startup, updater e recovery foram revisadas para evitar hashes e exceções cruas na interface. Detalhes técnicos permanecem destinados a logs/diagnósticos.
- Installer e diagnostics não ganharam nova superfície: o instalador continua gerenciado pela stack existente e o diagnóstico continua sanitizado/fail-closed.

## CONFIRMADO EM TESTES

- Contratos de branch/base, canais, artifact policy, diagnóstico, supply chain, updater, rollback, backup/restore, recovery, installer, portable e proteção do banco permanecem automatizados.
- O gate RC verifica headings deste relatório, caminhos de scripts referenciados pelos workflows, ausência dos rollback scripts obsoletos, proteções do updater, runtime empacotado, mensagens de UI auditadas e preservação de `validation.json` como `not-run`.
- O gate de órfãos verifica que não restem `CloudOS.Host.exe`, `CloudOS.Bootstrap.exe`, `CloudOS.WslCore.exe` nem backend Node identificável após a sequência automatizada do Windows.
- O hardening do instalador continua provando ausência de dependência de Node global e Go global no produto distribuído.

## CONFIRMADO EM CI

- O workflow Productization Batch 2 executa Linux completo e, somente após sucesso dele, Windows completo.
- A CI RC executa o gate estático nos dois jobs; o Windows também executa orphan check e mede os artefatos realmente gerados.
- Resultado da CI do HEAD final deste RC deve ser obtido do GitHub Actions; este documento não antecipa estado verde.

### Métricas RC

A fonte de verdade é `artifacts/audit/release-candidate-metrics.json`, criado pelo job Windows. Somente entradas com `status: measured` possuem número válido.

- Startup WebOnly: **não medido**. O fluxo real depende da sessão/UI e hosted CI não representa readiness interativo de usuário.
- Startup Full: **não medido**. O fluxo real depende do Host nativo/interativo e hosted CI não substitui o gate físico/visual.
- Shutdown: **não medido** enquanto não houver um ciclo representativo de startup + encerramento do produto em ambiente apropriado.
- Memória dos principais componentes: **não medida**; processos de build/teste não representam memória de runtime.
- Instalador: **medido pela CI Windows** em bytes + SHA-256.
- Portátil: **medido pela CI Windows** em bytes + SHA-256.
- Update full: **medido pela CI Windows** em bytes + SHA-256.
- Update delta: medido somente se Velopack realmente gerar um delta; ausência de delta não é convertida em número nem falha artificial de RC.
- Diagnósticos: **medido pela CI Windows** em bytes + SHA-256.

## CONFIRMADO EM VALIDAÇÃO FÍSICA

Nenhum item. O gate físico não foi executado e `productization/validation.json` deve permanecer com `status=not-run` e `visualValidation=not-run` até a execução explícita em máquina física.

## NÃO CONFIRMADO

- Tempo de startup WebOnly até sessão utilizável.
- Tempo de startup Full até janela utilizável.
- Tempo de shutdown de um ciclo Full real.
- Consumo de memória representativo de Host, Bootstrap, backend e WSL core em uma sessão física.
- Comportamento visual do instalador, shortcuts, janela Host e fluxos de usuário em máquina física.
- Smoke real do WSL core quando não existe distro no runner hospedado.
- Assinatura Authenticode e cadeia de confiança de produção.
- “Zero órfãos” para todo símbolo/arquivo semântico do repositório: o gate RC prova a superfície operacional auditada e processos residuais conhecidos, não uma análise formal de alcançabilidade de cada símbolo.

## RISCOS

- O candidato continua `unsigned-development`; não é apropriado para promoção/distribuição final.
- A CI hospedada não substitui validação física/visual, principalmente para WSL, WebView2, atalhos e lifecycle de janelas/processos.
- Tempos de startup/shutdown e memória precisam de definição objetiva de início/readiness/fim em host representativo; medir build/teste seria enganoso.
- O scanner de segredos de artefato é um gate de alta confiança e não substitui uma plataforma corporativa de secret scanning.

## DÍVIDAS TÉCNICAS

- Vite ainda reporta chunk principal acima de 500 kB e sobreposição de import dinâmico/estático em `appRegistry.ts`; não é bloqueio de productization e não será aberto como frente no RC.
- GitHub Actions pode avisar sobre actions que ainda declaram Node 20 e são forçadas pelo runner para Node 24; o runtime do produto continua pinado separadamente.
- `actions/setup-go` pode avisar que não encontra `go.sum` na raiz porque o módulo Go é aninhado; build/teste do módulo continuam explícitos.
- Há repetição deliberada de regressões entre workflows de linhas diferentes. Consolidar workflows é trabalho pós-RC somente se preservar gates/branch scopes sem reduzir evidência.
- O build reprodutível precisa de Node, .NET e Go na toolchain de CI; isso é distinto da exigência de runtime distribuído sem Node/Go globais.

## PÓS-RC

1. Executar `Validar Distribuição CloudOS.cmd` em máquina física, sem ajuste manual dos artefatos, e preservar evidências.
2. Registrar `validation.json`, screenshots, logs, banco/WSL/processos antes e depois.
3. Medir startup Full/WebOnly, shutdown e memória em ambiente representativo somente com readiness/lifecycle objetivos.
4. Executar validação visual separadamente.
5. Tratar assinatura/certificado e decisão de promoção em etapa separada.
6. Somente após evidência física/visual satisfatória discutir promoção ou distribuição.
