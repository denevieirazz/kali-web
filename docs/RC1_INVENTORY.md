# CloudOS — Inventário Funcional de Superfícies (RC1)

Data da Auditoria: 2026-09-05  
Versão Alvo: **21.0.0-rc.1**  
Classificações: `COMPLETE`, `PARTIAL`, `PLACEHOLDER`, `VISUAL_ONLY`, `BROKEN`, `MISSING`, `NOT_APPLICABLE`

---

## Matriz de Superfícies e Estado de Implementação

| Superfície | Classificação | Estado e Ações para o RC1 |
|---|:---:|---|
| **Desktop** | **PARTIAL** | Renderiza ícones e status. Falta persistência das posições dos ícones (`desktop_layout.json`), reflow inteligente quando resolução/DPI muda, seleção múltipla (`Ctrl+clique`) e menu de contexto completo (Novo Arquivo, Nova Pasta, Colar, Atualizar, Organizar, Ordenar, Personalizar, Abrir Terminal Aqui). |
| **Taskbar** | **COMPLETE** | Barra inferior com Start, Workspaces (1 a 4), botões de tarefas ativas, bandeja do sistema, relógio e botão de Mostrar Área de Trabalho (minimizar/restaurar). |
| **Start** | **PARTIAL** | Lista aplicativos CloudOS, Windows e WSL. Falta persistência de fixação (Pin/Unpin to Start), histórico delimitado de Recent Apps e busca profunda com deep-links para Configurações e pastas. |
| **Search (Spotlight)** | **PARTIAL** | Paleta central de busca. Falta busca tolerante simples (fuzzy) para encontrar páginas de Configurações, distros WSL e locais de Arquivos. |
| **Files (Arquivos)** | **PARTIAL** | Navegação por pastas Windows, WSL e drives. Falta transformar o placeholder da Lixeira em interface real com dados e ações nativas, segmentar breadcrumb clicável, persistir favoritos e suportar diálogo de propriedades. |
| **Lixeira CloudOS** | **VISUAL_ONLY** | Atualmente exibe apenas uma SnackBar avisando indisponibilidade. Será substituída por uma visualização funcional nativa (nome, caminho original, data de exclusão, tamanho, Restaurar, Excluir Definitivamente e Esvaziar Lixeira). |
| **Terminal** | **PARTIAL** | ConPTY real com abas e perfis PowerShell/CMD/WSL. Falta busca no histórico com `Ctrl+F`, menu suspenso de seleção de perfil no botão `+` e tratamento explícito de saída de processo com botão Reiniciar. |
| **Browser** | **PARTIAL** | WebView2 nativo in-process com controles básicos. Falta tela de recuperação de falhas do processo web, nova aba local (New Tab) com atalhos favoritos e visualizador de downloads. |
| **Settings (Configurações)** | **COMPLETE** | 13 seções cobrindo Display, Áudio, Energia, Armazenamento, Desempenho, Startup, Rede, Bluetooth, Personalização, WSL, Recuperação, Diagnósticos e Sobre. Polimento com cartões de resumo na página inicial e deep-linking. |
| **Quick Settings** | **COMPLETE** | Painel flyout rápido na bandeja com volume, Wi-Fi, Bluetooth, perfil de energia e atalho para Configurações com telemetria real. |
| **Notification Center** | **COMPLETE** | Central de notificações lateral com contagem de não lidas, agrupamento por aplicativo, botão Limpar Todas e histórico delimitado. |
| **Task Manager (Monitor)** | **PARTIAL** | Lista processos e métricas de memória/bateria. Falta proteção de segurança rígida (denylist) impedindo o encerramento acidental de processos críticos do Windows (`winlogon`, `csrss`, `lsass`, `services`, `smss`, `System`). |
| **Open With (Abrir Com)** | **COMPLETE** | Diálogo integrado ao Broker para escolher entre aplicativos CloudOS, Windows e Linux. |
| **Clipboard (Área de Transferência)** | **COMPLETE** | Histórico de texto seguro e delimitado com opção de limpar e desativar. |
| **Recovery (Recuperação)** | **COMPLETE** | Utilitário standalone `CloudOS.Recovery.exe` com status, verificação de 33 arquivos e restauração para o Windows Explorer. |
| **Diagnostics (Diagnósticos)** | **COMPLETE** | Painel com métricas de sistema, handles, threads, versão e botão de exportação sanitizada. |
| **Personalização** | **COMPLETE** | Temas Escuro/Claro/Auto, cores de destaque e papéis de parede persistentes. |
| **Display (Tela)** | **COMPLETE** | Mudança de resolução, taxa de atualização, orientação, escala e diálogo de confirmação com reversão automática. |
| **Áudio** | **COMPLETE** | Volume master, mudo e tratamento de eventos de dispositivos de áudio via CoreAudio. |
| **Rede & Wi-Fi** | **COMPLETE** | Visualização de adaptadores, IP, gateway e SSID; capability-driven sem simulações falsas. |
| **Bluetooth** | **COMPLETE** | Status do adaptador e dispositivos conhecidos via WinRT/Win32. |
| **Armazenamento** | **COMPLETE** | Capacidade, espaço livre e ocupado de unidades locais e de rede. |
| **Energia / Bateria** | **COMPLETE** | Percentual de bateria, status de carregamento ou indicação de rede elétrica. |
| **Desempenho** | **COMPLETE** | Perfis de desempenho (Economia, Equilibrado, Alto Desempenho) com amostragem eficiente. |
| **WSL e Linux** | **COMPLETE** | Listagem de distros, status, inicialização, terminal e visualização de arquivos. |
| **Sobre o CloudOS** | **COMPLETE** | Informações de versão, compilação, SHA do Git, arquitetura e licenças. |
| **Startup Automático** | **COMPLETE** | Gerenciamento via `HKCU\Run` e mutex de sessão única. |
| **Shell & Fallback** | **COMPLETE** | Infraestrutura preparada com supervisão, detecção de crash-loop e fallback para o Explorer. Persistent shell mantido **DESATIVADO (GATE 0)**. |
| **First Run (OOBE)** | **MISSING** | Assistente de boas-vindas ágil (< 1 min) com perfil de hardware automático e opções de Pular / Configurar depois. |

---

## Diretrizes de Eliminação de Placeholders

1. **Lixeira:** Substituição imediata do SnackBar informativo por uma lista real de itens excluídos com ações funcionais.
2. **Pin / Unpin to Start:** Ação real com persistência em disco.
3. **Persistência de Ícones do Desktop:** Posições salvas e carregadas com suporte a reflow automático.
4. **Proteção Denylist no Task Manager:** Bloqueio ativo de encerramento de processos essenciais do Windows com aviso claro.
5. **Busca Tolerante:** Pesquisa com deep-link direto para telas de configurações e pastas.
