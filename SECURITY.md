# CloudOS Native security boundary

O runtime de produto desta branch e nativo C++/Win32. O shell nao inicia Node, npm, Vite, WebView2, servidores HTTP/WebSocket, React, C# Host ou XAML.

## Processo e lifecycle

- processos criados pelo runtime usam Job Objects com kill-on-close quando a operacao exige ownership;
- ConPTY e criado com handles limitados ao processo filho;
- recursos Win32 sao liberados no shutdown;
- janelas ocultadas apenas por workspace sao restauradas antes do shell sair.

## Janelas

CloudOS gerencia janelas top-level reais. Nao existe promessa de quebrar fronteiras do Windows. UAC Secure Desktop, UIPI, processos protegidos, DRM, anti-cheat, AppContainer e outras politicas do sistema operacional continuam sendo respeitadas.

## WSL

WSL e opcional. APIs `wslapi` sao usadas onde fazem sentido; `wsl.exe` e usado para sessoes interativas ConPTY que a API nao representa. Nenhum comando recebido de uma pagina web existe no caminho de execucao desta versao.

## Processo Manager

O encerramento de processos exige selecao explicita e confirmacao. PID 0, PID 4 e o proprio CloudOS sao bloqueados no fluxo normal. O Windows ainda pode negar `PROCESS_TERMINATE` conforme ACL, integrity level e protecoes do processo.

## Contribuicoes

O CI rejeita a reintroducao de fontes `.js`, `.jsx`, `.ts`, `.tsx`, `.html`, `.css`, `.cs`, `.csproj` e `.xaml` na arvore final desta branch. Mudancas de baixo nivel devem manter warnings como errors no MSVC e preservar o gate de boot nativo.
