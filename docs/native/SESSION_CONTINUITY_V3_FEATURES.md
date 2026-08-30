# Session Continuity V3 — matriz funcional

Esta matriz enumera comportamentos e invariantes implementados pelo bloco. Ela não representa 100 subsistemas independentes; serve como checklist de regressão para o shell.

## Ledger e persistência

1. Store dedicado `continuity_v3.dat`.
2. Magic e versão próprios.
3. Preferências persistentes.
4. Último workspace persistente.
5. IDs monotônicos de checkpoint.
6. Sequência monotônica de eventos.
7. Limite máximo de checkpoints.
8. Limite máximo de eventos.
9. Limite máximo de janelas por checkpoint.
10. Limite máximo de string na desserialização.
11. Validação da versão antes de carregar.
12. Validação das contagens antes de alocar.
13. Arquivo temporário `.tmp`.
14. `FILE_FLAG_WRITE_THROUGH`.
15. `FlushFileBuffers`.
16. Backup `.bak` antes da promoção.
17. `MOVEFILE_REPLACE_EXISTING`.
18. `MOVEFILE_WRITE_THROUGH`.
19. Fallback automático para backup válido.
20. Journal registra recuperação pelo backup.
21. Reparo do próximo ID após load.
22. Reparo da próxima sequência após load.
23. Retenção configurável por workspace.
24. Retenção limitada a 1..32.
25. Intervalo de autosave limitado a 5..3600 s.
26. Rotação do journal.
27. Limpeza explícita de checkpoints.
28. Limpeza explícita do journal.

## Checkpoints

29. Checkpoint possui ID estável.
30. Checkpoint possui workspace.
31. Checkpoint possui FILETIME.
32. Checkpoint possui motivo.
33. Checkpoint possui coleção de janelas.
34. Janela registra processo.
35. Janela registra classe Win32.
36. Janela registra trecho do título.
37. Janela registra monitor device.
38. Janela registra geometria normalizada.
39. Janela registra floating.
40. Janela registra `showCmd`.
41. Captura usa todas as janelas gerenciadas da área.
42. Geometria é relativa à work area do monitor.
43. Coordenadas normalizadas são limitadas.
44. Restauração converte para a work area atual.
45. Monitor original é preferido quando ainda existe.
46. Há fallback se o monitor desapareceu.
47. Tamanho mínimo evita janela degenerada.
48. Checkpoint pode representar área vazia.
49. Último checkpoint por workspace é consultável.
50. Checkpoint específico é consultável por ID.

## Matching e restauração

51. HWND não é tratado como identidade persistente.
52. PID não é tratado como identidade persistente.
53. Processo incompatível elimina candidato.
54. Classe incompatível elimina candidato.
55. Título compatível aumenta score.
56. Cada HWND só satisfaz um registro.
57. Matching exige score mínimo.
58. Restauração usa `RestoreWindowState` do Window Manager.
59. Floating é restaurado.
60. Workspace é restaurado.
61. Estado maximizado pode ser restaurado.
62. Estado minimizado pode ser restaurado.
63. Estado normal pode ser restaurado.
64. Restauração pode trocar para o workspace do checkpoint.
65. Sucesso/falha é registrado no journal.
66. Quantidade de janelas correspondidas é registrada.
67. Processo externo arbitrário não é relançado.
68. `CreateProcessW` não pertence ao daemon.
69. `ShellExecuteW` não pertence ao daemon.
70. `SetParent` cross-process não pertence ao daemon.

## Daemon residente

71. Serviço singleton por processo.
72. Registro automático pelo Window Manager.
73. Engine em `HWND_MESSAGE`.
74. Timer de 2 segundos.
75. Não usa low-level keyboard hook.
76. Não usa CBT hook.
77. Detecta workspace atual.
78. Detecta foreground atual.
79. Calcula assinatura de geometria/estado.
80. Autosave exige intervalo vencido.
81. Autosave exige assinatura alterada.
82. Área sem mudança não gera checkpoint repetido.
83. Saída de workspace pode gerar checkpoint.
84. Troca de workspace é journalizada.
85. Foco pode ser journalizado.
86. Journal de foco é opcional.
87. Preferências podem desativar o serviço operacional.
88. Serviço lembra último workspace.
89. Estado é salvo após mudanças relevantes.
90. UI pode solicitar refresh sem recriar daemon.

## Crash marker e resume

91. Marker dedicado `continuity_v3.live`.
92. Marker contém PID.
93. Marker contém FILETIME.
94. Marker é criado com write-through.
95. Marker ausente indica último encerramento limpo.
96. Marker restante indica sessão interrompida.
97. Sessão interrompida é registrada no journal.
98. Recovery pós-crash é configurável.
99. Retomar último workspace é configurável.
100. Recovery ocorre após o message loop poder processar o daemon.
101. Checkpoint mais recente da área é escolhido.
102. Falta de checkpoint não causa relançamento arbitrário.
103. Encerramento normal salva o ledger.
104. Encerramento normal remove o marker.

## Central de Continuidade

105. Janela Win32 top-level própria.
106. Não usa WebView2.
107. Não usa React.
108. Usa material visual nativo do CloudOS.
109. Página Sessão.
110. Página Checkpoints.
111. Página Journal.
112. Página Preferências.
113. Sessão lista workspace.
114. Sessão lista título.
115. Sessão lista processo.
116. Sessão lista floating/gerenciada.
117. Sessão lista show state.
118. Duplo clique pode focar janela.
119. Foco pode mudar para a área da janela.
120. Botão Salvar agora.
121. Botão Restaurar último.
122. Atalho para Workspace Studio.
123. Checkpoints aparecem em ordem reversa.
124. Checkpoints exibem ID.
125. Checkpoints exibem timestamp.
126. Checkpoints exibem nome do workspace.
127. Checkpoints exibem motivo.
128. Checkpoints exibem quantidade de janelas.
129. Checkpoint selecionado pode ser restaurado.
130. Estado atual pode ser capturado manualmente.
131. Exclusão de checkpoints pede confirmação.
132. Journal exibe timestamp.
133. Journal exibe tipo de evento.
134. Journal exibe workspace.
135. Journal exibe título.
136. Journal exibe detalhe.
137. Limpeza do journal pede confirmação.
138. Preferência de enable editável.
139. Autosave editável.
140. Recovery pós-crash editável.
141. Retomada de workspace editável.
142. Journal de foco editável.
143. Intervalo editável.
144. Retenção editável.
145. Preferências possuem reset para padrão.
146. `Ctrl+S` salva estado pela Central.
147. `Esc` esconde a Central sem destruir o daemon.

## Descoberta e atalhos

148. `Ctrl+Alt+Shift+C` abre a Central.
149. `Ctrl+Alt+Shift+K` cria checkpoint.
150. `Ctrl+Alt+Shift+L` restaura o último checkpoint.
151. Hotkeys usam `MOD_NOREPEAT`.
152. Falha de uma hotkey não aborta o shell.
153. Desktop possui `Central de Continuidade...`.
154. Workspace Studio continua separado.
155. Central de Comandos continua separada.

## Identidade de workspace

156. Nome vem do profile do Workspace Studio.
157. Não existe segundo store de nomes.
158. Há nome simples.
159. Há nome numerado.
160. Há nome compacto com ellipsis.
161. Há texto de status com layout.
162. Texto de status informa auto-tiling.
163. Texto de status informa auto-launch.
164. Journal usa nomes configurados.
165. Central usa nomes configurados.

## Invariantes de segurança/arquitetura

166. CloudOS continua sendo shell/session environment sobre Windows NT.
167. Nenhuma mudança de Winlogon faz parte do bloco.
168. Shell Launcher não é ativado.
169. Aplicativos externos permanecem HWND top-level do Windows.
170. WebView2 continua reservado ao Browser CloudOS.
171. Recovery de geometria é conservador.
172. File operations não são reexecutadas pelo Continuity daemon.
173. Conteúdo de memória de processo não é serializado.
174. Documento de terceiro não é modificado para permitir checkpoint.
175. O ledger pode ser removido sem corromper o store do Workspace Studio.
176. Snapshots explícitos do Workspace Studio ficam separados dos checkpoints rotativos.
177. O build oficial executa o contrato de Session Continuity antes do MSVC.
178. O projeto MSVC lista explicitamente todos os TUs do bloco.
