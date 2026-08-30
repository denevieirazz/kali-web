# Superficies nativas responsivas

Problemas observados nas capturas locais: owner-draw deixa cantos brancos,
flyouts maiores que a area util, lista de notificacoes truncada e repintura do
desktop inteiro em idle. A implementacao continua Win32, sem hospedar paginas.

Fontes consultadas antes da alteracao:
- https://learn.microsoft.com/en-us/windows/win32/controls/create-an-owner-drawn-list-box
- https://learn.microsoft.com/en-us/windows/win32/controls/scroll-a-bitmap-in-scroll-bars
- https://learn.microsoft.com/en-us/windows/win32/api/shlwapi/nf-shlwapi-shloadindirectstring
- https://learn.microsoft.com/en-us/windows/win32/api/oleacc/ns-oleacc-msaamenuinfo
- https://github.com/microsoft/Windows-classic-samples (licenca MIT verificada)
- Exemplo CppWindowsOwnerDrawnMenu no microsoftarchive/msdn-code-gallery-microsoft
  (cabecalho declara Ms-PL; consultado somente como referencia, sem copiar codigo).

Decisoes: preservar controles nativos e suas mensagens/teclado; pintar toda a
area dos botoes; usar listbox com strings acessiveis e cards nas notificacoes;
limitar tamanho ao monitor e permitir rolagem; tematizar apenas menus criados
pelo CloudOS, sem interferir em extensoes IContextMenu do Windows. Recursos
indiretos de audio sao resolvidos pela API oficial com fallback legivel.
Os menus owner-draw expoem nomes por MSAAMENUINFO, mantido no primeiro membro
dos dados do item, conforme o contrato documentado de Active Accessibility.
Buffers do desktop devem ser reutilizados e atualizacoes dinamicas separadas
do wallpaper/atalhos. Codigo novo original; nenhuma fonte externa copiada.

Validacao: contratos, compilacao Release isolada e testes comportamentais de
geometria/pintura. Escalas/monitores e operacoes reais de hardware que nao forem
exercitados devem permanecer explicitamente nao validados no relatorio.
