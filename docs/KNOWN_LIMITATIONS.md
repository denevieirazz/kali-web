# CloudOS — Limitações Conhecidas (Release Candidate 1)

Este documento descreve limitações conhecidas do estado atual do CloudOS no marco **RC1**.

---

## 1. Confinamento e Modo de Execução

- **Gate 0 Ativo**: O CloudOS opera atualmente como um ambiente de apresentação e gerenciamento de janelas em modo usuário sobre o Windows. O Windows Explorer (`explorer.exe`) continua sendo o shell oficial registrado no sistema (`HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`). A substituição permanente de shell está desativada por política de segurança no RC1.
- **Confinamento em Modo Usuário**: O CloudOS não instala drivers de modo kernel nem serviços de sistema de segundo plano com privilégios SYSTEM. Todas as operações utilizam APIs padrão Win32 e chamadas RPC autenticadas via Named Pipe com a identidade do usuário logado.

---

## 2. Subsistema Linux (WSL2 / WSLg)

- **Dependência do Subsistema**: O suporte a ferramentas e aplicações Linux depende da instalação prévia do WSL2 no host Windows com pelo menos uma distribuição registrada (ex: Ubuntu). Se o WSL não estiver presente, as abas de terminal WSL e atalhos Linux permanecem desabilitados, mas o CloudOS opera normalmente com ferramentas Windows nativas.
- **Janelas WSLg**: Janelas gráficas do Linux são gerenciadas pelo compositor WSLg integrado do Windows. O rehoming direto para o interior de frames Flutter depende dos limites do DWM e pode ser renderizado em janelas separadas dependendo do toolkit X11/Wayland utilizado pelo app.

---

## 3. Navegador Integrado (WebView2)

- **Microsoft Edge WebView2 Runtime**: Requer o runtime do WebView2 instalado no sistema (padrão no Windows 10/11 atualizados). Se ausente, o Navegador exibe aviso de dependência.
- **Isolamento de Extensões**: O navegador interno não carrega extensões de terceiros da Chrome Web Store nem sincronização de perfil em nuvem proprietária do Edge/Chrome.
- **Certificados e Protocolos Customizados**: Certificados TLS inválidos são bloqueados por padrão sem opção de bypass na interface de usuário.

---

## 4. Hardware e Aceleração Gráfica

- **Perfil Econômico Automático**: Em dispositivos com menos de 4 GB de memória RAM livre ou gráficos integrados legados, o CloudOS desativa automaticamente efeitos de desfoque translúcido (*backdrop blur*) e animações pesadas para manter a taxa de quadros estável a 60 FPS.
- **Captura Multi-Monitor**: A enumeração de janelas em configurações multi-monitor com taxas de DPI mistas (ex: tela 4K a 150% e monitor secundário 1080p a 100%) realiza compensação contínua via Win32 Per-Monitor V2 DPI Awareness, mas pequenas divergências visuais momentâneas durante o arraste entre telas podem ocorrer até a conclusão da transição pelo DWM.
