# WORKFLOW AUDIT — CloudOS Batch 3

Base congelada: `be36ba9d01f207f56b03c9f5e824e500b83b8e22`

Escopo: produtividade diária entre CloudOS local (OPFS), grants Windows e Linux Home, sem alterar Browser nativo, WSL Core v2, instalador, updater, rollback, backup/restore ou pipelines de Productization RC.

## Dados confirmados no código

### Workspace

Uma criação de Workspace provisiona, na origem escolhida, uma raiz `Workspaces/<nome-id>` com sete diretórios fixos:

1. `Notes`
2. `Downloads`
3. `Evidence`
4. `Reports`
5. `Files`
6. `Terminal`
7. `Browser`

Também grava `workspace.json` com nome, descrição, data, último acesso, origem e estrutura. O índice de Workspaces é metadata local; não usa o banco real do produto.

**Operações de setup automatizadas por Workspace:** 8 operações mínimas que antes precisariam ser realizadas individualmente para obter a mesma estrutura (7 diretórios + 1 manifesto). Isso é contagem de operações de filesystem, não contagem de cliques humanos.

### Terminal aqui

- Linux Home: implementado dentro do CloudOS. O Files abre o CloudOS Terminal e, somente após a sessão WSL estar conectada, envia um `cd` validado relativo ao `$HOME`.
- OPFS: não há path de sistema operacional; o Terminal real não pode receber um cwd correspondente sem criar outra tecnologia de bridge.
- Windows grant: File System Access entrega um handle autorizado, não um path físico confiável para o PowerShell. O Release Freeze impede adicionar uma bridge nativa só para expor esse path.

O backend continua rejeitando `cwd`, `command`, executável e argumentos arbitrários no handshake do Terminal.

### Pontes entre providers

As ações `Enviar para Linux`, `Enviar para Windows` e `Copiar para Workspace` são assistidas:

- exigem confirmação explícita;
- não movem o arquivo de origem;
- não sobrescrevem nome já existente no destino;
- aceitam somente arquivo regular nesta fase;
- rejeitam symlink;
- têm limite de 256 MiB por transferência assistida;
- exigem destino montado/disponível;
- um Windows grant ausente exige seleção explícita do usuário.

O paste normal continua bloqueando clipboard de provider diferente. Portanto a ponte não converte o Files em cross-provider automático.

### Clipboard Global

- limite: 30 entradas;
- limite por entrada: 5 MiB;
- payload textual armazenado no OPFS privado;
- metadata limitada em localStorage;
- password input não é capturado;
- padrões de JWT, private key, Bearer auth, password/secret/api key/tokens/credentials e credenciais em URL são rejeitados;
- copiar, colar, favoritar e limpar estão disponíveis;
- fontes CloudOS DOM identificadas: Files, Terminal e Workspace Notes.

**Limite:** o Browser nativo roda fora da árvore DOM do frontend congelado. Seu clipboard não é observado pelo listener do Batch 3 sem alterar essa integração.

### Notes

Notes usa Markdown simples em arquivos `.md` do Workspace. Há lista de notas como abas, autosave com debounce de 650 ms, pesquisa, preview simples e atalhos `Ctrl+N`, `Ctrl+S` e `Ctrl+F`. Não foi criado editor rico nem tecnologia nova.

### Downloads

O Workflow registra um destino explícito entre Workspace atual, OPFS, Windows grant e Linux Home.

**Não está conectado ao download do Browser nativo.** O Browser nativo está congelado e sua API atual não expõe ao frontend um callback de download com destino. A preferência não é apresentada como roteamento efetivo enquanto essa restrição existir.

### App Launcher

`Alt+Espaço` abre busca para aplicações, Workspace, Notes, arquivos já indexados pelo Files e Configurações. `Ctrl+Shift+P` é fallback quando o host/SO intercepta `Alt+Espaço`.

A indexação de arquivos é incremental: somente diretórios que o usuário já abriu no Files entram no índice local. Não existe crawler em background.

### Window management

Metade esquerda, metade direita, maximizar e restaurar usam o Window Manager existente. Atalhos dentro do CloudOS:

- `Alt+Shift+Esquerda`
- `Alt+Shift+Direita`
- `Alt+Shift+Cima`
- `Alt+Shift+Baixo`

`Meta/Win+Esquerda` e `Meta/Win+Direita` também são tratados quando o WebView recebe esses eventos; o Windows pode interceptá-los antes do CloudOS.

### Evidence

Evidence fica em `Evidence` por Workspace. O hub salva nota, log, link, arquivo e imagem do clipboard quando a permissão de clipboard de imagem está disponível.

## Quantos cliques foram removidos?

**Não medido em uso físico.** Nenhum número de “cliques removidos” é declarado como resultado real antes de um estudo reproduzível do fluxo anterior e do Batch 3.

Dado objetivo disponível sem inventar: a criação do Workspace automatiza 8 operações mínimas de filesystem; Terminal Aqui Linux elimina a digitação manual do `cd`; o launcher elimina a necessidade de navegar pelo Menu Iniciar para itens encontrados pelo índice. Converter isso em “cliques” depende da sequência usada pelo usuário e deve ser medido no gate de uso real.

## Quantas telas foram evitadas?

**Não medido em gate físico.** O código concentra Notes, Evidence, Downloads preference, Clipboard e atalhos do Workspace no mesmo hub e usa overlays para Launcher/Clipboard, mas não há telemetria que permita converter isso honestamente em um número de telas evitadas.

## Quantas mudanças entre Windows / CloudOS / Linux ainda existem?

Matriz confirmada:

| Fluxo | Saída da UI CloudOS necessária? | Estado |
|---|---:|---|
| Files OPFS → arquivo no Linux Home | Não | ponte assistida |
| Files Linux Home → OPFS | Não, via `Copiar para Workspace` quando Workspace é OPFS | ponte assistida |
| Files OPFS/Linux → Windows grant já montado | Não | ponte assistida |
| Primeiro acesso a Windows grant | Sim, seletor de pasta do sistema | necessário para consentimento |
| Files Linux → Terminal na mesma pasta | Não | implementado |
| Files OPFS → Terminal real na mesma pasta | Sim / não representável como cwd | limitação estrutural |
| Files Windows grant → Terminal real na mesma pasta | Sim / path físico não exposto pelo grant | limitação estrutural |
| Browser nativo → destino inteligente de download | Integração não disponível no Batch 3 | congelado |

Não existe um único número agregado de “mudanças restantes” porque os fluxos têm condições diferentes. Há **três fronteiras ainda abertas** no escopo pedido: cwd real para OPFS, cwd real para Windows grant e roteamento de download do Browser nativo.

## Quanto contexto continua exigindo sair do CloudOS?

Confirmado:

- seletor Windows para conceder/reconceder grant;
- qualquer necessidade de abrir Terminal real exatamente no OPFS;
- qualquer necessidade de abrir Terminal real exatamente no path físico escondido pelo Windows grant;
- escolha efetiva do destino de download no Browser nativo enquanto sua integração permanecer congelada.

Não foi medida duração nem frequência dessas saídas. Portanto não há percentual de “contexto retido” declarado.

## Interpretação do Batch 3

O Batch 3 reduz navegação interna e cria pontes explícitas usando primitivas já presentes. Ele **não elimina todas as fronteiras Windows ↔ CloudOS ↔ Linux** e não tenta escondê-las com automação implícita. Onde o Release Freeze impede cumprir o requisito literalmente, o estado é registrado como limitação em vez de ser marcado como concluído.
