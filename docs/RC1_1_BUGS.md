# CloudOS RC1.1 — Registro de Correções e Bugs Mitigados

Este documento detalha todos os bugs reais, inconsistências e vulnerabilidades mitigadas durante a rodada de Engenharia de Release RC1.1.

---

## 1. Discrepância e Fragmentação de Versão

- **Problema:** Múltiplas superfícies da interface do usuário (ex: aba de Diagnósticos, tela Sobre o CloudOS, manifestos) continham versões fixas desatualizadas (`1.0.0-rc1`, `21.0.0 Stage 8.5`, SHA `1d6cfd03`).
- **Causa Raiz:** Ausência de uma fonte canônica única em código para metadados de release no Flutter.
- **Solução Implementada:** Criação da classe singleton `CloudOSVersion` em `cloudos_version.dart`, centralizando `productVersion = 21.0.0-rc.1.1`, `buildNumber = 32`, `releaseName = Release Candidate 1.1` e Git SHA correspondente. Todas as telas agora consomem essa autoridade.

---

## 2. Inexistência de Compilação do Instalador Real Inno Setup

- **Problema:** O script Inno Setup `CloudOS.iss` existia, mas o compilador `ISCC.exe` não estava instalado e não havia automação para gerar o executável final de instalação.
- **Causa Raiz:** Dependência externa do Inno Setup 6 não resolvida no ambiente de desenvolvimento.
- **Solução Implementada:** Instalação oficial do Inno Setup 6.7.3 via winget, resolução dinâmica do caminho do `ISCC.exe` no pipeline, atualização das diretivas do script `.iss` para a release `21.0.0-rc.1.1` e geração automática do `CloudOS-Setup-21.0.0-rc.1.1-x64.exe` com seu checksum SHA256.

---

## 3. Risco de Instalação em Pastas Críticas do Sistema

- **Problema:** Um usuário poderia acidentalmente selecionar a raiz `C:\` ou pastas de sistema como `C:\Windows` no instalador Inno Setup.
- **Causa Raiz:** Falta de evento `NextButtonClick` com validação de caminho no código Pascal do `.iss`.
- **Solução Implementada:** Adicionado bloco em `[Code]` no `CloudOS.iss` que rejeita instalações na raiz de volumes, no diretório do Windows, em `System32` ou na pasta de arquivos temporários `%TEMP%`.

---

## 4. Falta de Proteção contra Downgrades no Atualizador

- **Problema:** O updater em `CloudOS.Maintenance.ps1` verificava apenas a compatibilidade de protocolo, permitindo que uma versão com build inferior substituísse uma build mais recente.
- **Causa Raiz:** Comparação de números de build ausente na validação pré-staging.
- **Solução Implementada:** Adicionada verificação de `buildNumber`. Caso o novo pacote possua uma build menor que a instalada, a operação é rejeitada com `UPDATE_REJECTED`, exigindo o parâmetro explícito `-Force`.

---

## 5. Risco de Corrupção e Sobrescrita Ilimitada de Preferências

- **Problema:** Em caso de travamento durante a gravação das preferências ou JSON corrompido, a recuperação dependia de apenas um arquivo `.bak`, e não havia quarentena do arquivo com erro.
- **Causa Raiz:** Falta de rotação limitada de backups e de tratamento resiliente para JSON truncado.
- **Solução Implementada:** `CloudOSPreferences` foi atualizado para:
  - Migração de Schema v1 -> v2 com sanitização e clamping de coordenadas.
  - Quarentena automática do arquivo corrompido para `.corrupt.<timestamp>`.
  - Rotação delimitada de até 5 backups (`preferences.backup.1..5.json`).

---

## 6. Falta de Validação de Nomes de Dispositivos Reservados do DOS no Gerenciador de Arquivos

- **Problema:** Usuários podiam tentar criar ou renomear arquivos/pastas para `CON`, `PRN`, `AUX`, ou terminar nomes com ponto ou espaço, causando erros na API do Windows.
- **Causa Raiz:** Validação de entrada ausente na interface Flutter antes da chamada ao Broker.
- **Solução Implementada:** Implementada a rotina `_validateFileName` em `files_window.dart` que bloqueia antecipadamente nomes reservados e caracteres proibidos com mensagens em português do Brasil.

---

## 7. Risco de Encerramento dos Processos do Supervisor e Broker

- **Problema:** O Gerenciador de Tarefas continha na denylist apenas processos nativos do Windows (`winlogon`, `csrss`, etc.), mas permitia tentar finalizar `CloudOS.Supervisor.exe`.
- **Causa Raiz:** Ausência dos binários de supervisão do CloudOS na lista `_criticalProcesses`.
- **Solução Implementada:** Inclusão de `cloudos.supervisor`, `cloudos.systembroker` e `cloudos.recovery` na lista de proteção do Task Manager.
