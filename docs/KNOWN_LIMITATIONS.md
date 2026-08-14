# CloudOS — Limitações Conhecidas

Este documento descreve limitações conhecidas do estado atual. Ele não transforma recursos experimentais em estáveis.

## Navegador Nativo

- O Navegador CloudOS abre em uma janela WPF top-level separada do desktop React. Ele ainda não é renderizado dentro do Window Manager React.
- Sites externos usam um WebView2/profile separado e não recebem a bridge privilegiada CloudOS.
- O profile do Browser persiste cookies/cache no UDF dedicado até que o usuário use a ação explícita de limpar dados.
- A restauração da última sessão é opt-in. Ela restaura somente URLs HTTP/HTTPS sanitizadas e estado de pin; não restaura formulários, comandos, POST bodies ou credenciais.
- A nova aba é uma superfície WPF; não existe página HTML privilegiada compartilhada com conteúdo externo.
- `WebResourceRequested` é usado para a política HTTP(S), mas a fronteira WebSocket do terminal é protegida adicionalmente pelo backend por Origin + JWT.
- Save Page/Print dependem das capacidades do WebView2/Windows e podem ter comportamento diferente conforme tipo de documento/site.
- Certificado TLS inválido não possui bypass na UI.
- Protocolos externos (`mailto:`, handlers customizados etc.) são bloqueados em vez de enviados ao Windows.
- O navegador não possui extensões, sync em nuvem ou password manager CloudOS.
- DevTools do Browser só devem ser habilitados por `CLOUDOS_BROWSER_DEVTOOLS=1` em desenvolvimento explícito. CDP remoto de produção não é configurado pela feature.
- Os testes WebView2 reais exigem Windows com WebView2 Runtime e Chromium do Playwright.
- O smoke completo do Host deve rodar no GitHub Actions Windows ou VM/Sandbox descartável; por segurança o script recusa um perfil CloudOS local existente fora de CI.

## Host/desktop já existentes

- Docking Win32/WSLg continua sujeito a limitações de DPI/multi-monitor documentadas na arquitetura.
- Encerramento abrupto externo do processo Host pode depender do lease/timeout dos componentes Windows/WSLg para limpeza de processos fora da posse direta do Host.
- O modo de substituição total do shell do Windows permanece fora do fluxo padrão.

## Critério de release

Uma limitação pode ser removida deste arquivo somente depois de:

1. teste automatizado ou smoke reproduzível;
2. validação Windows verde;
3. documentação da nova garantia;
4. nenhuma alteração de banco/OPFS/WSL implícita para alcançar o resultado.
