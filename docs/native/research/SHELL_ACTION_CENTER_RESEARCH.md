# CloudOS Native — pesquisa para Central de Comandos e camada de ações do shell

## Objetivo

Este bloco amplia o CloudOS de um conjunto pequeno de atalhos para uma camada de ações de shell pesquisável e auditável. A Central de Comandos não finge implementar internamente subsistemas que já pertencem ao Windows. Ela agrega pontos de entrada reais do CloudOS, URIs oficiais do Windows Settings, utilitários clássicos do sistema e ações de sessão em uma interface Win32 nativa.

A regra arquitetural continua a mesma das fases anteriores: CloudOS é o shell/desktop environment da sessão; Windows continua fornecendo kernel, DWM, drivers, segurança, Settings e utilitários administrativos. O CloudOS orquestra esses recursos sem tentar reparentar processos arbitrários.

## Fontes primárias consultadas

### Microsoft Learn — Launch Windows Settings

https://learn.microsoft.com/windows/apps/develop/launch/launch-settings

A Microsoft documenta o esquema `ms-settings:` como o mecanismo oficial para abrir páginas específicas do aplicativo Configurações. A documentação também deixa claro que a disponibilidade de cada página pode depender da versão do Windows, SKU, hardware e recursos instalados.

Decisão CloudOS:

- ações de configuração usam URIs `ms-settings:` documentadas;
- a Central não considera falha de URI como prova de corrupção do CloudOS;
- páginas indisponíveis em uma edição específica do Windows podem simplesmente não abrir;
- nenhuma URI é apresentada como uma API privada ou garantida em todas as versões.

### Microsoft Learn — ShellExecuteW / ShellExecuteExW

https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shellexecutew
https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shellexecuteexw

`ShellExecuteW` e `ShellExecuteExW` são pontos de entrada do Shell para abrir arquivos, aplicações e alvos registrados. Isso é apropriado para Settings, consoles `.msc`, applets `.cpl` e executáveis do Windows.

Decisão CloudOS:

- alvos pertencentes ao Windows são lançados como janelas top-level normais;
- o DWM continua responsável pela composição dessas janelas;
- a Central de Comandos não volta a usar `SetParent` ou `WS_CHILD` para capturar aplicações de terceiros;
- aplicações realmente integradas ao CloudOS continuam sendo abertas pelas classes nativas do próprio CloudOS.

### Microsoft Learn — LockWorkStation

https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-lockworkstation

O bloqueio da estação é uma operação suportada explicitamente por `LockWorkStation`.

Decisão CloudOS:

- a ação **Bloquear** usa `LockWorkStation` diretamente;
- não existe simulação visual de lock screen dentro do CloudOS.

### Microsoft Learn — Desktop Application Toolbars / AppBar

https://learn.microsoft.com/windows/win32/shell/application-desktop-toolbars

O Windows oferece a infraestrutura AppBar (`SHAppBarMessage`) para barras de desktop que reservam espaço de trabalho e recebem notificações do Shell.

Decisão desta fase:

- a Central de Comandos não finge que a taskbar atual já é uma AppBar completa;
- a migração futura da taskbar CloudOS deve avaliar `ABM_NEW`, `ABM_QUERYPOS`, `ABM_SETPOS`, auto-hide, multi-monitor e mudanças da work area;
- essa evolução é separada do catálogo de ações para não misturar arquitetura de taskbar com despacho de comandos.

## Inventário funcional desta fase

O catálogo nativo contém **106 ações reais** organizadas assim:

| Categoria | Quantidade | Exemplos |
| --- | ---: | --- |
| CloudOS | 15 | Browser, Files, Projetos, Terminal, WSL, Drive, Monitor, Configurações, Executar |
| Sistema | 36 | Tela, áudio, energia, armazenamento, Windows Update, segurança, Task Manager, Device Manager |
| Rede | 13 | Wi-Fi, Ethernet, VPN, Proxy, Hotspot, Bluetooth, impressoras, USB |
| Personalização | 11 | Wallpaper, cores, temas, fontes, lock screen, Start, taskbar, teclado virtual |
| Privacidade / acessibilidade / pesquisa | 13 | Câmera, microfone, localização, filesystem, Narrador, Lupa, teclado, mouse, pesquisa |
| Apps / contas / idioma / jogos | 12 | Apps instalados, defaults, startup, contas, login, data, idioma, Game Mode, Game Bar |
| Sessão | 6 | Lock, reiniciar CloudOS, sair do CloudOS, logoff, reiniciar Windows, desligar Windows |
| **Total** | **106** | |

## Comportamento da Central de Comandos

A UI é uma janela Win32 nativa, não HTML. Ela fornece:

1. pesquisa incremental;
2. tokenização da consulta;
3. correspondência por ID, título, descrição, palavras-chave e alvo;
4. filtro por categoria;
5. lista em modo relatório com duas colunas;
6. seleção única;
7. execução por botão;
8. execução por Enter;
9. execução por duplo clique;
10. `Ctrl+F` para voltar à pesquisa;
11. `F5` para reconstruir resultados;
12. `Esc` para fechar;
13. seta para baixo na caixa de busca para entrar na lista;
14. contagem de resultados;
15. contagem total do catálogo;
16. CPU real no rodapé;
17. RAM real no rodapé;
18. espaço livre real em disco quando disponível;
19. atualização periódica das métricas;
20. ações destrutivas de energia com confirmação explícita;
21. ações CloudOS despachadas pelo `NativeAppLauncher`;
22. Settings despachado por `ms-settings:`;
23. utilitários clássicos despachados pelo Shell;
24. lock via API Win32;
25. reinício do próprio shell sem reiniciar o Windows.

## Política para ações de energia

Reiniciar ou desligar o Windows não deve acontecer por clique acidental. A camada de ações exige confirmação antes de executar os comandos do sistema. O CloudOS nunca chama essas ações automaticamente no startup, em timer ou por resultado de busca.

## Compatibilidade e verdade na UI

Alguns URIs `ms-settings:` são condicionais. A Central deve manter a distinção entre:

- **ação registrada no catálogo** — existe como ponto de entrada conhecido;
- **ação disponível nesta máquina** — depende da versão/SKU/feature do Windows;
- **ação executada com sucesso** — depende da resposta real do Shell.

Isso evita a regressão para mensagens falsas do tipo “100% operacional” quando o recurso subjacente não existe no sistema atual.

## Critérios de não regressão

Os contratos automatizados desta fase devem falhar se:

- o build voltar a compilar o launcher legado com `SetParent`;
- a Central deixar de ser compilada;
- a camada de ações tiver menos de 100 entradas reais;
- o navegador voltar a enviar Google para um host externo;
- o catálogo perder ações representativas de Windows Settings, rede, utilitários clássicos ou sessão;
- ações destrutivas perderem confirmação;
- a pesquisa deixar de filtrar o catálogo;
- a UI deixar de expor execução por teclado e duplo clique.

## Próximas fronteiras

Depois de estabilizar este bloco no MSVC e no Windows real, a evolução correta do shell passa por separar ainda mais infraestrutura: taskbar AppBar verdadeira, Start popup independente, registro de janelas CloudOS, notificações, tray, multi-monitor, persistência de layout, recovery de sessão e integração com eventos de mudança de display/work area. Essas fases devem reutilizar a camada de ações em vez de duplicar comandos por toda a interface.
