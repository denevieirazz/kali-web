# POC1_PREFLIGHT_REPORT.md

## STATUS DE ENTREGA

**AUTOMAÇÃO IMPLEMENTADA. EXECUÇÃO FÍSICA AINDA NÃO REALIZADA NESTE AMBIENTE.**

Este arquivo registra o contrato da entrega do `Linux Runtime Preflight`.

O relatório factual da máquina física será gerado automaticamente por esse comando em:

```text
poc1-physical-evidence/POC1_PREFLIGHT_REPORT.md
```

Artefatos associados:

```text
poc1-physical-evidence/WINDOW_BASELINE.json
poc1-physical-evidence/screenshots/
poc1-physical-evidence/logs/preflight-<run>.log
poc1-physical-evidence/telemetry/preflight-<run>.json
```

## REGRA DE VEREDITO

Enquanto o comando não tiver terminado no PC físico:

```text
GO/NOGO = NO GO
PRONTO PARA CLICAR ABRIR XCLOCK = NÃO
```

Isso não representa falha da arquitetura. Representa apenas ausência de execução física do preflight.

O relatório gerado no PC real contém `PASS`, `WARN` ou `FAIL`, componente, causa e evidência para cada item e para cada boundary:

```text
WSL
↓
DISTRO
↓
XPRA
↓
TRANSPORTE
↓
PROXY
↓
IFRAME
```

## O QUE O COMANDO FAZ

`Linux Runtime Preflight` executa, sem iniciar xclock:

1. valida o host Windows e o WSL;
2. resolve e aquece a distro existente;
3. confirma `xpra`, `xpra-html5`, `xpra-x11` e localiza `xclock` sem executá-lo;
4. valida opções CLI necessárias ao runtime real;
5. inspeciona displays `:100..:149`;
6. inspeciona portas `14500..14549`;
7. bloqueia sessões/ledger incompatíveis com uma prova limpa;
8. prepara `screenshots/`, `logs/` e `telemetry/` e testa escrita;
9. captura `WINDOW_BASELINE.json` com processos, títulos e `MainWindowHandle`;
10. inicia um Xpra seamless efêmero sem `--start-child`;
11. valida `xpra info`;
12. valida WSL → Windows loopback TCP;
13. valida Xpra HTML5 HTTP direto;
14. valida WebSocket Xpra direto;
15. valida HTTP pelo capability proxy CloudOS;
16. valida WebSocket pelo mesmo proxy usado pela POC1;
17. carrega o cliente Xpra em iframe oculto dentro do CloudOS e exige `connection-established`;
18. encerra o dry run;
19. confirma display morto, porta fechada, WebSocket fechado e ledger sem referência conflitante;
20. grava relatório, log e telemetria.

## GARANTIA DE ESCOPO

O Dry Run não contém:

```text
--start-child
--exit-with-children
xclock
xeyes
xterm
gedit
firefox
gimp
```

Ele não instala dependências e não abre Stage 2, Batch 5, IA, Productization, Browser novo, catálogo, marketplace ou App Manager.

## PRÓXIMO GATE

Somente quando o relatório físico terminar com:

```text
Decision: GO
PRONTO PARA CLICAR ABRIR XCLOCK: SIM
```

a primeira prova de containment deve começar.

Até lá, **xclock não deve ser executado pela automação de preflight**.
