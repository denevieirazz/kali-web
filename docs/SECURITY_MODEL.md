# CloudOS — Modelo de Segurança (Security Model)

O CloudOS foi concebido sob princípios rigorosos de **mínimo privilégio**, **contenção em modo de usuário** e **não interferência na segurança do sistema hospedeiro**.

---

## 1. Princípios Arquiteturais de Segurança

| Princípio | Implementação no CloudOS |
|---|---|
| **Zero Drivers de Kernel** | Toda a execução do CloudOS reside estritamente em Ring 3 (User Mode). Nenhum driver de modo kernel (`.sys`) é instalado ou carregado. |
| **Sem Serviços Globais Privilegiados** | O CloudOS não cria serviços do Windows rodando como `SYSTEM` ou `LocalService`. Todos os processos rodam na conta do usuário logado. |
| **GATE 0 (Preservação do Shell do Windows)** | O Windows Explorer (`explorer.exe`) permanece ininterruptamente como o shell oficial da máquina. Não há substituição do Winlogon no registro global (`HKLM`). |
| **Comunicação IPC Segura (DACL Restritiva)** | A comunicação entre o Flutter Shell e os binários C++ ocorre via Named Pipe local protegido por DACL (Discretionary Access Control List) que autoriza unicamente o SID do usuário atual. |
| **Fail-Closed em Falhas de Handshake** | Se um cliente não autenticado ou com token inválido tentar conectar no Named Pipe, a conexão é encerrada imediatamente sem execução de comandos. |
| **Proteção de Processos Críticos** | O Gerenciador de Tarefas do CloudOS implementa salvaguarda rígida impedindo o encerramento de processos vitais do Windows (`winlogon`, `csrss`, `lsass`, `services`, `smss`, `System`, `svchost`, `explorer`, `dwm`) e componentes core do CloudOS (`CloudOS.Supervisor.exe`, `CloudOS.SystemBroker.exe`). |
| **Proteção de Diretórios do Sistema** | Operações de exclusão de arquivos no CloudOS bloqueiam tentativas de remover pastas do sistema (`C:\Windows`, `C:\Program Files` e raízes de volume). |
| **Sanitização de Nomes de Arquivo** | Criação e renomeação de arquivos validam palavras reservadas do DOS/Windows (`CON`, `PRN`, `AUX`, `NUL`, etc.) e caracteres proibidos (`<>:"/\|?*`). |

---

## 2. Isolamento de Dados e Limites de Confiança

1. **Configurações do Usuário:**
   - Gravadas exclusivamente em `%LOCALAPPDATA%\CloudOS\preferences-v1.json`.
   - Isolamento completo: nenhuma chave de personalização é gravada nas áreas de políticas restritas do Windows (`HKLM` ou `HKCU\Policies`).
2. **Navegador Embutido (WebView2):**
   - Roda em processo separado gerenciado pelo runtime Microsoft Edge Evergreen.
   - Perfil de dados e cookies ficam confinados em `%LOCALAPPDATA%\CloudOS\WebView2Data`.
3. **Sessões WSL:**
   - Conexões de terminal com distribuições WSL utilizam os canais oficiais `wsl.exe` com a autoridade de usuário atribuída pela instalação Linux configurada.
