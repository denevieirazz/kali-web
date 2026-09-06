# CloudOS RC1.2 — Roteiro de Testes e Validação do Usuário (QA)

Este documento fornece um guia passo a passo para o usuário Douglas validar fisicamente todas as superfícies do CloudOS Release Candidate 1.2 (`21.0.0-rc.1.2`, Build 33).

---

## 1. Validação do Instalador Oficial

1. Localize o instalador oficial gerado em:
   `dist\releases\21.0.0-rc.1.2\CloudOS-Setup-21.0.0-rc.1.2-x64.exe`
2. Verifique o checksum SHA256 no PowerShell:
   ```powershell
   Get-FileHash dist\releases\21.0.0-rc.1.2\CloudOS-Setup-21.0.0-rc.1.2-x64.exe -Algorithm SHA256
   ```
   - O hash deve ser exatamente: `45a86456b432aa50d909806a0f7d793f0b4cc246e439db5946baf2509b6a2111`
3. Execute o instalador graficamente (ou silenciosamente com `/VERYSILENT`).
4. Verifique que a pasta padrão sugerida é:
   `%LOCALAPPDATA%\Programs\CloudOS`
5. Teste tentar instalar em `C:\Windows` ou `C:\` e confirme que o instalador bloqueia a ação com uma mensagem amigável.
6. Conclua a instalação e confirme a criação do atalho no Menu Iniciar.

---

## 2. Inicialização Segura e Conformidade

1. Execute o CloudOS pelo atalho ou via script de inicialização segura:
   ```powershell
   pwsh -NoProfile -File scripts/flutter/start-cloudos-v21-integrated.ps1
   ```
2. Verifique o tempo de carregamento da interface (geralmente abaixo de 2 segundos).
3. Abra o aplicativo **Configurações** (pelo Menu Iniciar ou atalho):
   - Vá na seção **Sobre o CloudOS**:
     - Confirme que a versão exibida é `21.0.0-rc.1.2 (Release Candidate 1.2)`.
     - Confirme a Build `33`.
     - Verifique o rodapé institucional: `CloudOS Provedor de Shell Autônomo para Windows.`
   - No rodapé do **Menu Iniciar**:
     - Confirme que o nome de usuário exibido corresponde ao seu usuário ativo do Windows (obtido dinamicamente via ambiente, sem valores fixos).

---

## 3. Teste de Operações no Gerenciador de Arquivos (Files)

1. Abra o **Gerenciador de Arquivos** no dock ou Menu Iniciar.
2. Crie uma pasta de teste e tente criar um arquivo chamado `CON` ou `AUX`.
   - Confirme que o aplicativo exibe mensagem de alerta informando que trata-se de nome reservado do Windows.
3. Crie arquivos com caracteres Unicode/acentuados (`teste_ação.txt`, `日本語.txt`) e confirme a leitura normal.
4. Tente colar um arquivo sobre outro com o mesmo nome e confirme o surgimento da caixa de diálogo de conflito (Substituir / Cancelar).

---

## 4. Teste de Proteção do Gerenciador de Tarefas

1. Abra o **Gerenciador de Tarefas do CloudOS**.
2. Na aba de processos do sistema, localize o Windows Explorer (`explorer.exe`) ou o Supervisor (`CloudOS.Supervisor.exe`).
3. Clique em **Finalizar**:
   - Confirme que o CloudOS exibe um diálogo com ícone de escudo bloqueando a finalização com a mensagem explicativa:
     *"O processo ... é essencial para o funcionamento do Windows e da sessão ativa. Por segurança, o CloudOS impede sua finalização forçada..."*

---

## 5. Teste de Reparo e Reversão

1. Para testar a rotina de autorreparo atômica:
   ```powershell
   pwsh -NoProfile -File scripts/installer/CloudOS.Maintenance.ps1 -Action repair -InstallDir "$env:LOCALAPPDATA\Programs\CloudOS"
   ```
2. Confirme que todos os 33 arquivos do pacote são verificados por hash SHA256 e quaisquer arquivos ausentes ou corrompidos são restaurados.

---

## 6. Verificação do Gate 0

Antes e depois de todos os testes, rode a salvaguarda:
```powershell
pwsh -NoProfile -File scripts/safety/assert-gate0.ps1
```
- A saída deve confirmar que `effective_shell` é `explorer.exe` e `userinit_intact` é `True`.
