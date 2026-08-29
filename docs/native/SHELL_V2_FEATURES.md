# CloudOS Shell V2 — matriz funcional do bloco multi-HWND

Este bloco preserva as 106 ações da Central de Comandos e adiciona infraestrutura de desktop. As funções abaixo são comportamentos implementados no código compilado ou ferramentas explícitas do repositório.

## Desktop

1. Desktop em HWND próprio.
2. Desktop ocupa a tela virtual multi-monitor.
3. Wallpaper padrão desenhado por GDI+.
4. Wallpaper customizado persistente.
5. Seletor Win32 de wallpaper.
6. Crop proporcional cover.
7. Sincronização opcional com wallpaper Windows via SPI.
8. Enumeração real de FOLDERID_Desktop.
9. Ícones reais de arquivos via SHGetFileInfoW.
10. Duplo clique em item do Desktop.
11. Atalhos CloudOS separados de arquivos reais.
12. Nova pasta pelo menu de contexto.
13. Novo TXT pelo menu de contexto.
14. Abrir Desktop no Files CloudOS.
15. Abrir Terminal no Desktop.
16. Abrir Central de Comandos pelo desktop.
17. Abrir configurações de Tela.
18. Abrir Personalização.
19. Restaurar wallpaper padrão.
20. Refresh do desktop.

## Drag and drop

21. IDropTarget real.
22. RegisterDragDrop.
23. RevokeDragDrop.
24. CF_HDROP.
25. Drop de múltiplos arquivos.
26. Drop de pastas.
27. IFileOperation para cópia.
28. Undo record quando suportado.
29. Refresh após drop.
30. Notificação após drop.

## Taskbar / AppBar

31. Taskbar em HWND próprio.
32. ABM_NEW.
33. ABM_QUERYPOS.
34. ABM_SETPOS.
35. ABN_POSCHANGED.
36. ABM_REMOVE.
37. Reserva real de work area.
38. Uma AppBar por monitor.
39. Workspaces 1–4 clicáveis.
40. Botão Start.
41. Apps fixados.
42. Lista de tarefas por monitor.
43. Foco de janela pela taskbar.
44. Estado da janela ativa.
45. Relógio/data reais.
46. Bateria na área de status quando disponível.
47. Botão Quick Settings.
48. Contador de notificações.
49. Menu de energia no botão direito.
50. Atualização periódica da taskbar.

## Start

51. Start em HWND independente.
52. Popup por monitor.
53. Pesquisa incremental.
54. Busca semântica existente do NativeSearchEngine.
55. Lista de app + descrição.
56. Navegação por teclado.
57. Enter para abrir.
58. Duplo clique para abrir.
59. Escape para fechar.
60. Fecha ao perder ativação.
61. Recentes via MRU.
62. Atalho para Central de Comandos.
63. Menu de energia.

## Task Switcher

64. Seletor em HWND próprio.
65. DwmRegisterThumbnail.
66. DwmQueryThumbnailSourceSize.
67. DwmUpdateThumbnailProperties.
68. DwmUnregisterThumbnail.
69. Previews ao vivo.
70. Somente workspace atual.
71. Seleção visual.
72. Tab/setas para navegar.
73. Enter/click para ativar.
74. Escape para cancelar.
75. Tentativa de Alt+Tab.
76. Fallback Ctrl+Alt+Tab.
77. Alt+Shift+Tab reverso quando disponível.
78. Auto-commit após ciclo.

## Quick Settings

79. Flyout em HWND próprio.
80. Endpoint de áudio padrão via MMDevice.
81. Leitura de volume real.
82. Slider de volume real.
83. Mute/unmute real.
84. Estado AC/DC.
85. Percentual de bateria.
86. Contagem de monitores.
87. Wi-Fi Settings.
88. Bluetooth Settings.
89. Network Settings.
90. Display/brightness Settings.
91. Sound Settings.
92. Power Settings.

## Notificações

93. Notification Center próprio.
94. Histórico de até 100 itens.
95. Contador de não lidas.
96. Marcar como lidas ao abrir.
97. Limpar histórico.
98. Eventos de startup.
99. Eventos de wallpaper.
100. Eventos de mudança de monitor.
101. Eventos de drag-and-drop.

## Multi-monitor / sessão shell

102. EnumDisplayMonitors.
103. GetMonitorInfoW.
104. Bounds da tela virtual.
105. Detecção de alteração de topologia.
106. Reconstrução de AppBars ao hotplug.
107. Mover janela para monitor adjacente.
108. Preservar posição relativa ao mover.
109. Preservar estado maximizado.
110. Tentativa Win+Shift+Left/Right.
111. Fallback Ctrl+Alt+Shift+Left/Right.
112. WindowManager usa rcWork real da AppBar.
113. Tiling continua manual.
114. Desktop não contém Start/taskbar embutidos no build V2.
115. Script opcional de Shell Launcher oficial.
116. Validação de edição Enterprise/Education/IoT.
117. Configuração por WESL_UserSetting.
118. Confirmação PowerShell de alto impacto.
119. Remoção reversível do shell customizado por SID.
120. Contrato automatizado V2 de não regressão.

Somadas às 106 ações pesquisáveis da Central de Comandos, a fase deixa de depender de quantidade de cards e passa a ter infraestrutura de shell verificável por contratos.
