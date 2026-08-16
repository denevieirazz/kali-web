# Problemas conhecidos — Stabilization Batch 1

## Bloqueadores do lote

### Terminal: `dimensions` undefined

Evidência física aponta para o lifecycle visual do xterm durante `Terminal.open`, viewport/renderer, `ResizeObserver` e `FitAddon`. O transporte WSL Core v2 não é a origem do stack e não deve ser reimplementado para corrigir este defeito.

A versão oficial usa os pacotes legados `xterm@^5.3.0` e `xterm-addon-fit@^0.8.0`. A correção deve primeiro tornar open/fit/resize/dispose seguros; migração de pacote só será feita se testes demonstrarem necessidade.

### Browser em sessão sem Native Host

O launcher React atual tenta abrir o Browser mesmo quando `window.chrome.webview`/nonce não existem. O usuário recebe `NATIVE_HOST_UNAVAILABLE` e botão de retry, embora nenhuma tentativa possa ativar o Host naquela sessão. Em WebOnly/UXValidation o app deve ser marcado como indisponível por design e indicar modo Full.

### Files fragmentado entre branches

- linha oficial: OPFS;
- branch transacional: OPFS + pasta Windows autorizada + Linux Home;
- branch de UX: ícones, lista/grade e miniaturas sobre o Files antigo.

O Batch 1 precisa produzir um único `CloudOSFiles` com os três providers e UX compartilhada, mantendo cross-provider fail-closed.

### Launcher e diagnóstico

Falhas de backend/frontend podem morrer antes de produzir arquivo de readiness; launchers antigos podem então reportar apenas timeout. O launcher consolidado deve capturar stdout/stderr desde o spawn e interromper a espera imediatamente quando o processo morrer.

### Onboarding/recovery

Senha mínima de quatro caracteres é decisão explícita desta fase. A UX deve alertar que senha curta é fraca e recomendar frase maior, sem impor composição artificial. O recovery deve ser apresentado como arquivo/código offline de uso único, sem persistência automática do segredo.

## Não bloqueadores deliberadamente fora deste lote

- promoção do Browser físico candidato;
- promoção/retomada do System Center Linux/cgroups;
- VHD/VHDX real;
- substituição de Explorer/Shell Launcher em produção;
- transferência cross-provider no Files;
- agentes de IA com acesso a arquivos; capabilities próprias serão uma etapa futura.
