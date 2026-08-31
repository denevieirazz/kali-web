# CloudOS V22 — Files & Open With Security Blueprint

## 1. Princípios de Segurança

O gerenciador de arquivos e o sistema de associações do CloudOS V22 seguem os seguintes requisitos mandatórios:

1. **Princípio do Menor Privilégio**:
   - `CloudOS.SystemBroker.exe` e o `FileServiceV22` executam sob a conta do usuário logado comum.
   - Nenhuma operação de deleção, cópia, movimentação ou renomeação requer privilégios de Administrador.

2. **Prevenção de Execução de Código Arbitrário**:
   - Não existe método exposto para execução arbitrária de comandos bash/cmd/PowerShell.
   - Lançamentos de executáveis ocorrem através de APIs Win32 explícitas (`ShellExecuteExW`, `CreateProcessW`) com listas brancas de executáveis conhecidos e argumentos sanitizados.

3. **Integridade de Caminhos e Long Paths**:
   - Suporte completo a Unicode UTF-8 e UTF-16 em todos os nomes de arquivos (acentos, emojis, kanji).
   - Prefixação `\\?\` quando aplicável para contornar o limite histórico de 260 caracteres (`MAX_PATH`) do Win32.
   - Normalização canônica via `GetFullPathNameW` para evitar travessia de diretório não intencional (`..\..\`).

4. **Preservação de Dados do Usuário**:
   - Exclusões por padrão utilizam a Lixeira (`IFileOperation` / `FOF_ALLOWUNDO`), permitindo restauração imediata pelo usuário no Windows Explorer ou CloudOS Trash.
   - Exclusão permanente requer sinalizador explícito (`permanent: true`).

5. **Associações de Aplicativos (Open With)**:
   - Abertura de arquivos com aplicativos Windows não adultera as chaves `UserChoice` protegidas do Registro do Windows.
   - Lançamentos de aplicativos Linux no WSL2 utilizam `xdg-open` ou `gtk-launch` isolados por distribuição.
