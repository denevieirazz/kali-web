# CloudOS Visual Experience V6

## Objetivo

Visual Experience V6 e a linguagem visual nativa do CloudOS para C++/Win32. Ela substitui a interpretacao excessivamente literal do antigo frontend de referencia por uma hierarquia visual desenhada para composicao nativa, DWM e GDI+.

O frontend React antigo continua existindo apenas como referencia historica. Ele nao define mais valores de cor imutaveis e nao participa do build do shell.

## Principios

1. **Grafite profundo, nao preto chapado**
   - `BgSolid`: camada mais profunda.
   - `BgPrimary`: janela/flyout.
   - `BgSecondary`: paineis.
   - `BgTertiary`: controles e inputs.
   - `BgElevated`: cards/itens elevados.

2. **Indigo como identidade, nao como preenchimento universal**
   - Indigo forte e reservado para foco, selecao, acao primaria e estados ativos.
   - Cyan funciona como luz secundaria/ambiental e nao como segundo tema inteiro.

3. **Profundidade nativa**
   - `DrawElevatedPanel` combina sombra curta, borda, top highlight e glow opcional.
   - Botoes owner-draw possuem hover, pressed, focus e estados de perigo/acao primaria.
   - Superficies grandes evitam parecer um conjunto de `STATIC`, `BUTTON` e `LISTVIEW` crus.

4. **Ambient light sutil**
   - `PaintWindowBackground` usa gradiente grafite e glows indigo/cyan de baixa opacidade.
   - Glow nunca pode competir com legibilidade.

5. **DWM continua autoritativo para janela**
   - Dark mode, rounded corners, caption color e backdrop sao aplicados via atributos DWM quando suportados.
   - Nenhum efeito visual justifica reparentar processo externo.

6. **Tipografia e densidade**
   - Segoe UI Variable Display para titulos e labels de destaque.
   - Segoe UI Variable Text para chrome e conteudo.
   - Cascadia Mono permanece apropriada para texto tecnico/preview de codigo.
   - Espacamento deve separar grupos funcionais, nao criar vazio sem significado.

## Tokens V6 iniciais

- `BgSolid = RGB(5, 7, 12)`
- `BgPrimary = RGB(9, 13, 21)`
- `BgSecondary = RGB(14, 20, 31)`
- `BgTertiary = RGB(22, 29, 44)`
- `BgElevated = RGB(30, 39, 57)`
- `Accent = RGB(124, 92, 255)`
- `AccentHover = RGB(154, 126, 255)`
- `AccentCyan = RGB(77, 208, 225)`
- `TextPrimary = RGB(245, 247, 252)`
- `RadiusXL = 20`

Esses valores sao uma baseline, nao um contrato eterno. Contratos devem proteger a existencia da hierarquia sem impedir evolucao futura intencional.

## Files & Storage V5

Files V5 usa uma variante ainda mais profunda do mesmo sistema:

- sidebar e toolbar possuem tons proprios;
- address/search usam surface dedicada;
- grandes cards recebem sombra curta e highlight superior;
- `IExplorerBrowser` continua fornecendo o namespace Windows enquanto o chrome CloudOS permanece first-party;
- preview, tabs, Quick Access e file operations devem parecer parte do mesmo app, nao janelas independentes coladas umas nas outras.

## Start e Taskbar

Start V4 e Taskbar V4 herdam os novos tokens imediatamente. Passes subsequentes devem priorizar:

- cards elevados para estados ativos/hover;
- grupos com hierarquia clara em vez de linhas soltas;
- icones reais acima de iniciais sempre que o Shell oferecer um icone;
- selecao com accent/glow controlado;
- alinhamento consistente em monitores ultrawide e high-DPI;
- feedback visual para drag/reorder, overflow e grupos de janelas.

## Regras de regressao

Nao reintroduzir:

- Desktop/Start/Taskbar React como runtime;
- cores antigas exigidas literalmente apenas porque existiam no CSS de referencia;
- `WS_EX_CLIENTEDGE` como linguagem visual de inputs;
- superficies brancas dentro de chrome CloudOS quando um provider Shell puder receber dark treatment;
- `SetParent` de janelas externas para obter efeito visual;
- WebView2 fora do Browser CloudOS como atalho para desenhar UI nativa.

## Validacao

Os contratos nativos devem verificar:

- namespace `WebSkin`;
- hierarquia `Bg*`;
- accent primario e secundario;
- `DrawRoundedPanel` e `DrawElevatedPanel`;
- `PaintWindowBackground`;
- owner-draw buttons;
- `WindowSkinSubclass`;
- materiais DWM para flyout/janela.

O teste final continua sendo visual e funcional em Windows real: contraste, DPI, multi-monitor, hover, foco, clipping, performance de paint e consistencia entre superficies.
