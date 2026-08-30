# CloudOS Start V4 + Taskbar V4 — produtividade

Este documento descreve os controles reais do shell nativo compilado do CloudOS. O frontend antigo continua apenas como referencia visual; Start, Taskbar, janelas, previews e persistencia abaixo sao C++/Win32.

## Start V4

### Home

Ao abrir o Start sem pesquisa, a Home mostra:

- **Fixados** em grade;
- **Recomendados** calculados a partir do historico real de uso;
- **Todos** para abrir o catalogo completo;
- busca unificada entre aplicativos CloudOS e aplicativos indexados do Windows.

Os recomendados usam uma pontuacao que combina **frequencia + recencia**. Um app usado recentemente volta a ganhar relevancia sem apagar a importancia de apps usados muitas vezes.

### Pesquisa e teclado

- Digitar: pesquisa imediatamente;
- `Seta para baixo`: entra nos resultados / lista completa;
- `Seta para cima`: move a selecao;
- `Enter`: abre o item selecionado;
- `Esc`: volta para a Home; na Home, fecha o Start;
- `F5`: reindexa os aplicativos do Windows.

### Menu de contexto

Resultados podem ser abertos, fixados/desafixados no Start, fixados/desafixados na Taskbar e, quando aplicavel, ter sua localizacao aberta no Explorer.

Itens fixados na Home tambem podem ser reorganizados pelo menu de contexto.

## Taskbar V4

A Taskbar e uma AppBar Win32 real e usa a geometria real dos grupos de tarefas para clique, menus e previews.

### Pins

- clique: abre o aplicativo;
- arrastar: reorganiza os pins persistentes;
- clique direito: abrir, fixar/desafixar do Start, desafixar da barra e mover esquerda/direita;
- excesso de pins: aparece em `+N`, sem perder itens.

### Janelas abertas

Janelas sao agrupadas por processo/classe. Grupos com mais de uma janela exibem contador e permitem escolher uma janela especifica.

Clique em uma tarefa unica alterna foco/minimizacao. Clique em um grupo abre o seletor de janelas.

Clique direito em uma tarefa permite:

- restaurar;
- minimizar;
- maximizar;
- mover para Area 1, 2, 3 ou 4;
- alternar modo flutuante;
- fechar a janela;
- fechar todas as janelas do grupo.

Excesso de grupos de tarefas tambem aparece em `+N`.

## Preview DWM ao vivo

Passar o mouse sobre uma tarefa usa `DwmRegisterThumbnail` sobre a janela real.

A preview mostra:

- miniatura DWM ao vivo;
- icone real da janela;
- titulo real;
- botao de fechar com estado hover;
- clique na miniatura restaura uma janela minimizada e traz para frente;
- clique do meio fecha a janela.

A preview nao calcula posicoes antigas da barra: ela pergunta a propria Taskbar V4 pelo hit-test/retangulo real atraves de `CLOUDOS_WM_TASKBAR_QUERY_HIT`.

## Controles de mouse da Taskbar

Com o cursor sobre a Taskbar:

- **roda para cima**: workspace anterior;
- **roda para baixo**: proximo workspace;
- a navegacao faz wrap entre as quatro areas;
- **Ctrl + roda**: move a janela ativa para a area de destino e entra nela;
- **botao lateral X1**: workspace anterior;
- **botao lateral X2**: proximo workspace;
- **clique do meio sobre uma tarefa**: fecha a janela atingida.

Esses controles complementam os hotkeys globais existentes e nao substituem os botoes 1–4 da barra.

## Hub de acesso rapido

O menu de energia/acesso rapido nao e mais uma lista plana. Ele e dividido em submenus funcionais:

### Acesso principal

- Central de Comandos (106 acoes);
- Navegador;
- Arquivos;
- CloudOS Drive.

### Terminais

- Terminal;
- PowerShell;
- WSL / Kali.

### Ferramentas

- Executar;
- Calculadora;
- Bloco de Notas;
- Captura de Tela;
- Monitor do Sistema;
- Gerenciador de Tarefas;
- Todos os Aplicativos.

### Sistema e configuracoes

- Configuracoes do CloudOS;
- Configuracoes do Windows;
- Wi-Fi e rede;
- Windows Update;
- Saude do Sistema.

### Sessao e energia

- Bloquear Windows;
- Reiniciar CloudOS;
- Sair do CloudOS;
- Reiniciar Windows;
- Desligar Windows.

As acoes destrutivas continuam passando pelas rotinas de confirmacao ja existentes do catalogo de acoes do shell.

## Persistencia resiliente

### Pins

O estado de Start + Taskbar e salvo em:

`%LOCALAPPDATA%\CloudOS\shell_pins_v1.dat`

A gravacao usa arquivo temporario, `FILE_FLAG_WRITE_THROUGH`, `FlushFileBuffers` e substituicao atomica. Depois de uma gravacao valida, o CloudOS mantem tambem:

`%LOCALAPPDATA%\CloudOS\shell_pins_v1.dat.bak`

Se o arquivo principal estiver incompleto/corrompido, a inicializacao valida todo o arquivo, tenta o backup e restaura o principal automaticamente.

### Historico de recomendacoes

O MRU do Start usa:

`%LOCALAPPDATA%\CloudOS\start_mru.dat`

Ele tambem possui `.bak`, leitura completa antes de aceitar o estado e restauracao automatica do backup quando necessario.

## Contratos de regressao

O CI da branch executa, antes do MSBuild:

- `test-cloudos-native-shell-contracts.ps1`;
- `test-native-web-ui-contract.ps1`;
- `test-taskbar-productivity-contract.ps1`.

O ultimo contrato protege explicitamente a geometria real da Taskbar V4, DWM preview, controles de mouse, persistencia com backup, ranking inteligente do Start e o hub hierarquico de acesso rapido.
