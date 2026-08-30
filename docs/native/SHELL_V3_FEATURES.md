# CloudOS Shell V3 — matriz funcional

Este bloco é incremental sobre o Shell V2. Ele preserva Desktop multi-HWND, AppBars, Start independente, Quick Settings, Notification Center, DWM Task Switcher, OLE Desktop drop, multi-monitor e as 106 ações da Central de Comandos.

## Snap Assist

1. Hook out-of-context para início de move/resize.
2. Hook de location change durante drag.
3. Hook de fim de move/resize.
4. Overlay visual sem ativação.
5. Overlay transparente para input.
6. Snap metade esquerda.
7. Snap metade direita.
8. Snap quadrante superior esquerdo.
9. Snap quadrante superior direito.
10. Snap quadrante inferior esquerdo.
11. Snap quadrante inferior direito.
12. Arrastar para topo maximiza.
13. Ctrl + borda esquerda cria 1/3.
14. Ctrl + borda direita cria 1/3.
15. Ctrl + topo escolhe 1/3 esquerdo.
16. Ctrl + topo escolhe 1/3 central.
17. Ctrl + topo escolhe 1/3 direito.
18. Shift + esquerda cria layout 2/3.
19. Shift + direita cria layout 2/3.
20. Zonas respeitam `rcWork` da AppBar.
21. Janelas encaixadas não brigam com o tiling global.
22. Shell/taskbars/flyouts são excluídos do detector de snap.

## Hover previews da taskbar

23. Subclass somente da AppBar do próprio CloudOS.
24. Delay de hover para evitar popup acidental.
25. Popup de preview independente.
26. `DwmRegisterThumbnail`.
27. `DwmQueryThumbnailSourceSize`.
28. Preservação de aspect ratio.
29. `DwmUpdateThumbnailProperties`.
30. Preview ao vivo.
31. `DwmUnregisterThumbnail` ao esconder.
32. Clique no preview foca a janela.
33. Botão fechar no preview envia `WM_CLOSE`.
34. Delayed hide entre taskbar e popup.
35. Preview limitado ao monitor/task list daquela AppBar.
36. Teardown automático quando a AppBar é destruída.

## Start Indexer

37. Indexer singleton em background.
38. Thread separado para enumeração.
39. COM STA inicializado no worker.
40. `FOLDERID_Programs`.
41. `FOLDERID_CommonPrograms`.
42. Enumeração recursiva de atalhos por usuário.
43. Enumeração recursiva de atalhos comuns.
44. Suporte `.lnk`.
45. Suporte `.url`.
46. Suporte `.exe` presente nas árvores Start.
47. Namespace `shell:AppsFolder`.
48. `BHID_EnumItems`.
49. `IEnumShellItems`.
50. Nome amigável via `SIGDN_NORMALDISPLAY`.
51. Parsing name via `SIGDN_DESKTOPABSOLUTEPARSING`.
52. Deduplicação por launch target.
53. Busca por título.
54. Busca por origem.
55. Busca por target.
56. Ranking exact.
57. Ranking prefix.
58. Ranking contains.
59. Fuzzy subsequence simples.
60. Integração dos resultados Windows com apps CloudOS.
61. Indicador de indexação na UI.
62. Contador de apps indexados.
63. F5 para reindexar.
64. Botão Reindexar.
65. Start permanece responsivo durante indexação.

## Operações de arquivos

66. Janela nativa `CloudOS.Native.FileOperations.v1`.
67. Seleção múltipla de arquivos.
68. Adição de pasta.
69. Remoção de itens da fila.
70. Seletor nativo de pasta destino.
71. `CLSID_FileOperation`.
72. `IFileOperation::CopyItem`.
73. `IFileOperation::MoveItem`.
74. `IFileOperation::PerformOperations`.
75. `IFileOperationProgressSink` próprio.
76. Callback de início.
77. Callback pre-copy.
78. Callback pre-move.
79. Callback `UpdateProgress`.
80. `IFileOperation::Advise`.
81. `IFileOperation::Unadvise`.
82. `GetAnyOperationsAborted`.
83. Undo record quando suportado.
84. Prompt de elevação do Shell quando necessário.
85. Worker COM separado para não travar a UI.
86. Botão Cancelar.
87. Cancelamento devolvido pelo progress sink.
88. Progress bar para copy/move.
89. Status textual da operação.
90. Notificação após sucesso.
91. Erro HRESULT explícito.
92. Confirmação antes de fechar com operação ativa.
93. Atalho no menu de contexto do Desktop.

## ZIP

94. File Save Dialog para criar ZIP.
95. Seletor de destino de extração.
96. Validação de arquivo `.zip` para extract.
97. Criação via `tar.exe -a -c -f`.
98. Extração via `tar.exe -xf`.
99. Processo archive sem console.
100. Marquee enquanto o backend não expõe percentual.
101. Cancelamento do processo archive iniciado pelo CloudOS.
102. Exit code não zero vira falha visível.
103. Ausência de `tar.exe` não é mascarada como sucesso.

## Session Recovery

104. Estado em `%LOCALAPPDATA%\\CloudOS\\session_v3.dat`.
105. Arquivo temporário antes do replace.
106. `MOVEFILE_REPLACE_EXISTING`.
107. `MOVEFILE_WRITE_THROUGH`.
108. Marker `session_v3.unclean`.
109. Detecção de sessão anterior não limpa.
110. Snapshot de class name.
111. Snapshot de title.
112. Snapshot de app id CloudOS.
113. Snapshot de PID externo.
114. Snapshot de workspace.
115. Snapshot de floating.
116. Snapshot de bounds.
117. Snapshot normal/maximized/minimized.
118. Restore de apps CloudOS conhecidos.
119. Restore de posição de janelas externas ainda vivas.
120. Nenhum relaunch arbitrário de executável externo.
121. Operações de arquivo são excluídas de replay automático.
122. Retry para aplicar geometria após app interno nascer.
123. Snapshot periódico.
124. Snapshot ao trocar/mover workspace por hotkey.
125. Snapshot antes de mudança de topologia de monitor.
126. Snapshot em `WM_QUERYENDSESSION`.
127. Saída limpa em `WM_ENDSESSION`.
128. Snapshot em `PBT_APMSUSPEND`.
129. Aviso de sessão recuperada na central de notificações.

## Watchdog

130. Mutex de sessão único.
131. Segundo launch manual não cria segundo desktop.
132. Segundo launch tenta trazer o Desktop existente para frente.
133. Helper `--watchdog <pid>`.
134. `OpenProcess` no PID da UI.
135. `WaitForSingleObject` no process handle.
136. Exit 0 não reinicia o CloudOS.
137. Exit anormal dispara relaunch.
138. Delay para liberar HWND/AppBar/mutex antes do relaunch.
139. Watchdog só inicia depois de `Initialize()` bem sucedido.
140. Restart existente continua compatível pelo mutex com espera curta.

## Window Manager recovery primitives

141. Snapshot de todas as janelas gerenciadas.
142. Consulta do workspace de um HWND.
143. Alteração explícita de floating por HWND.
144. Restore de workspace por HWND.
145. Restore de bounds por HWND.
146. Restore de maximizado.
147. Restore de minimizado.
148. Ocultação correta quando janela restaurada pertence a outro workspace.
149. Tiling continua desligado por padrão.
150. Nenhum `SetParent` cross-process reintroduzido.

A contagem desta fase descreve capacidades implementadas no bloco V3; ela não substitui teste comportamental no Windows real. O contrato automatizado apenas impede regressões estruturais e o build/teste local continua obrigatório.
