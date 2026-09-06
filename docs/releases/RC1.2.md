# CloudOS 21.0.0-rc.1.2 Release Notes

## Resumo do Release Candidate 1.2
O **CloudOS 21.0.0-rc.1.2 (Build 33)** representa o ciclo final de validação, compatibilidade e endurecimento de distribuição do CloudOS V21. Esta versão submete o sistema ao ciclo de vida de produto real, estresse de IPC, integridade de arquivos, independência estrita do repositório de desenvolvimento e segurança em conformidade com o GATE 0.

## Destaques da Versão

### 1. Instalador e Desinstalador Oficial Inno Setup
- **Artefato Oficial:** `dist/releases/21.0.0-rc.1.2/CloudOS-Setup-21.0.0-rc.1.2-x64.exe` (11.79 MB)
- **Hash SHA256:** `45a86456b432aa50d909806a0f7d793f0b4cc246e439db5946baf2509b6a2111`
- **Validação de Assinatura:** Declarado de forma transparente como `NotSigned` (Unsigned RC).
- **Metadados PE VersionInfo:**
  - `ProductName`: `CloudOS`
  - `ProductVersion`: `21.0.0-rc.1.2`
  - `FileVersion`: `21.0.0.33` (via Runner.rc e pubspec.yaml)
  - `Architecture`: `x64`
- **Salvaguardas de Instalação:** Bloqueio ativo no assistente Inno Setup contra diretórios críticos do Windows (`C:\`, `C:\Windows`, `%TEMP%`).
- **Instalação Limpa e Idempotente:** Testada com sucesso em caminhos contendo espaços (`%LOCALAPPDATA%\Programs\CloudOS RC12 Test Spaces`).
- **Independência do Repositório:** Binários instalados rodam 100% isolados da árvore de desenvolvimento Git.

### 2. Estresse de IPC e Robustez do System Broker
- **Benchmark Real de IPC:** 500 chamadas sequenciais de ping medindo latência e vazão.
  - **Vazão média:** 34.5 requisições/segundo
  - **Latência média:** 28.92 ms
  - **Latência mínima / máxima:** 10.36 ms / 33.70 ms
  - **Percentis:** P95 = 32.04 ms, P99 = 32.84 ms
- **Rejeição de Frames Superdimensionados:** Conexão encerrada imediatamente (`ReadFrame` fail-closed) ao receber cabeçalho superior a 1 MiB (`kMaxPayloadBytes = 1048576`).
- **Tratamento de Frames Malformados:** Resposta de erro estruturada `{"ok": false, "error": {"code": "invalid_request", ...}}` sem vazamento de memória ou travamento do broker.
- **Resiliência Pós-Ataque:** O broker continuou operacional e pronto para processar requisições legítimas após ataques de fuzzing.

### 3. Mecanismo de Atualização SemVer e Proteção contra Downgrade
- **Função `Compare-CloudOSSemVer`:** Implementada no script de manutenção com conformidade à especificação SemVer 2.0.0.
  - Suporta matriz de testes:
    - `21.0.0-rc.1 < 21.0.0-rc.2`
    - `21.0.9 < 21.0.10`
    - `22.0.0 > 21.99.99`
    - `21.0.0-rc.1.1 < 21.0.0-rc.1.2`
    - `21.0.0 > 21.0.0-rc.1`
- **Proteção Ativa:** Atualizações que resultem em downgrade SemVer ou build inferior são rejeitadas com erro explicativo, a menos que o parâmetro explícito `-Force` seja utilizado.

### 4. Operações de Arquivos e Integridade
- **Nomes de Dispositivos Reservados:** Rejeição comprovada de palavras reservadas do DOS/Windows (`CON`, `PRN`, `AUX`, `NUL`, `COM1-COM9`, `LPT1-LPT9`).
- **Suporte a Unicode:** Criação, leitura e manipulação de arquivos com caracteres UTF-8 e acentuação (`ação_config.json`, `日本語_ドキュメント.txt`).
- **Teste de Transferência Massiva de 100MB:** Cópia de arquivo de 100MB com cálculo e validação estrita de integridade bit-a-bit (SHA256 intacto).

### 5. Sanitização de Ambiente de Desenvolvimento
- **Eliminação de Nomes de Usuário Hardcoded:** Remoção de referências estáticas a caminhos e nomes de desenvolvedor (`dougl`) no código de produção; uso de `Platform.environment['USERNAME']` dinâmico no Menu Iniciar e licença genérica nas Configurações.
- **Limpeza de Logs Soltos:** Ausência de arquivos de depuração soltos (`debug.log`, `wm_debug.log`, `trace.txt`, `screen.png`) no diretório do projeto.
- **Delimitação de Histórico e Pins:** Preferências delimitadas em memória (máximo de 50 pins e 20 recentes).

### 6. Integração Contínua (CI) e Segurança
- **Novo Workflow GitHub Actions:** `.github/workflows/rc-validation.yml` automatiza a validação de contratos, integridade e segurança no Windows Server runner.
- **Varredura OSV Scanner:** Dependências Flutter (`pubspec.lock`) e pacotes C++ NuGet escaneados com ZERO vulnerabilidades conhecidas.
- **Varredura de Segredos:** Ausência de chaves privadas ou tokens em código.
- **Exportador de Diagnóstico:** Pacote ZIP anonimizado (`scripts/diagnostics/export-diagnostics-bundle.ps1`).

### 7. Conformidade GATE 0
- **Status do Shell Oficial:** `HKLM\...\Winlogon\Shell = explorer.exe` (100% preservado).
- **Userinit:** `C:\WINDOWS\system32\userinit.exe,` (intacto).
- **Persistência CloudOS:** NÃO ATIVADA (`HKCU\...\Winlogon\Shell` vazio).
