# Política de segurança do CloudOS Unified

## Escopo suportado

Apenas a versão mais recente da branch principal recebe correções ativas.

## Relatar uma vulnerabilidade

Não abra uma issue pública com tokens, credenciais, dados pessoais ou uma prova destrutiva. Envie descrição, componente, reprodução não destrutiva e impacto estimado para `denevieirazz@gmail.com`.

## Modelo de confiança

O CloudOS Local Agent executa sob a mesma conta Windows que o iniciou. Um terminal PowerShell ou WSL autenticado é um shell real dessa conta, não um sandbox. A instalação deve ser tratada como software local para um usuário confiável; não exponha o backend na rede e não encaminhe suas portas.

## Controles implementados

- bind exclusivo em `127.0.0.1` e validação de origem HTTP/WebSocket;
- primeiro acesso sem senha padrão, bcrypt com custo 12 em produção e JWT com segredo local aleatório;
- código de recuperação aleatório de 256 bits armazenado somente como hash, mostrado uma única vez e rotacionado após uso;
- limitação persistente de tentativas de recuperação, respostas genéricas e sem enumeração da conta;
- limitação persistente de tentativas de login, `Retry-After` e nenhum usuário/senha tentado salvo no throttle;
- sessão validada contra a conta e sua `authVersion`, permitindo revogação após recuperação;
- banco atômico com backup, migração preservando a conta e falha fechada se todas as cópias estiverem corrompidas;
- rotas nativas autenticadas e mutações WSL limitadas a administrador;
- executáveis e argumentos definidos no servidor, sempre com `shell: false` no agente Node;
- distribuições validadas contra inventário ou catálogo produzido pelo próprio WSL;
- aplicativos lançados por IDs opacos de um catálogo interno;
- apenas o broker allowlisted solicita UAC; o backend completo não roda elevado;
- segredos do backend removidos do ambiente de terminais e processos filhos;
- limite de payload JSON e logs de operação limitados;
- remoção destrutiva de distribuição não exposta até existir confirmação forte e backup.

## Controles do host nativo

- WebView2 só carrega a origem CloudOS validada e bloqueia navegação, popup, permissão e download não autorizados;
- manifest e health check autenticado vinculam run ID, instance ID, PID, parent PID, porta e processo iniciado;
- single-instance usa pipe limitado ao usuário atual e nunca encerra um PID vindo do manifest;
- a ponte JSON v1 valida origem, nonce da navegação, esquema, tamanho, taxa e uma allowlist pequena de métodos;
- o gerenciador de HWND aceita apenas processos lançados pelo catálogo, mesma sessão e integridade igual ou menor;
- IPC do broker deve usar named pipe com ACL do SID atual, nonce, expiração e mensagens versionadas;
- nenhum objeto COM/.NET genérico, linha de comando ou caminho livre é exposto ao JavaScript;
- apps com integridade maior, secure desktop ou conteúdo protegido devem usar fallback seguro;
- arquivos Windows/WSL devem ser limitados a raízes concedidas e proteger contra traversal, symlink e reparse points.

## Limites atuais do runtime web

O token de sessão ainda fica no armazenamento da origem WebView2. Aplicativos OSL/SDK executados dinamicamente não devem ser tratados como código não confiável nem descritos como sandbox: a CSP atual permite `unsafe-eval` por compatibilidade. Antes de aceitar pacotes de terceiros, esse runtime precisa ser isolado em Worker ou frame sem acesso à origem autenticada.

## Política para o futuro modo shell

Preparar o CloudOS como shell não autoriza modificar a instalação atual do Windows. Enquanto todos os portões de recuperação não estiverem aprovados, o projeto não deve habilitar Shell Launcher, definir `Winlogon\Shell`, remover Explorer, ocultar telas de erro ou aplicar políticas de bloqueio.

Uma ativação futura deve cumprir simultaneamente:

- edição do Windows oficialmente compatível e configuração por usuário, nunca global;
- conta administrativa separada que continue usando `explorer.exe`;
- bootstrap nativo independente de WebView2/Node, proteção contra crash-loop e last-known-good;
- WinRE, mídia de recuperação e chave BitLocker externa verificadas;
- pacote, instalador e broker assinados em localização protegida;
- atualização atômica com rollback e teste completo em VM descartável;
- UAC, secure desktop, Defender e Windows Update preservados.

O diagnóstico de prontidão é somente leitura. Itens não observáveis são reportados como manuais ou desconhecidos, nunca aprovados por suposição. Consulte `docs/SHELL-MODE-PLAN.md`.
