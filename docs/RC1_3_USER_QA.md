# CloudOS RC1.3 — Roteiro de Homologação e Validação do Usuário (QA)

Este documento fornece um guia prático para o usuário Douglas homologar fisicamente as superfícies e os endurecimentos de estabilidade do CloudOS Release Candidate 1.3 (`21.0.0-rc.1.3`, Build 34).

---

## 1. Validação do Instalador Oficial

1. Localize o executável oficial gerado pelo pipeline Inno Setup:
   `dist\releases\21.0.0-rc.1.3\CloudOS-Setup-21.0.0-rc.1.3-x64.exe`
2. Calcule e valide o checksum SHA256 no PowerShell:
   ```powershell
   Get-FileHash dist\releases\21.0.0-rc.1.3\CloudOS-Setup-21.0.0-rc.1.3-x64.exe -Algorithm SHA256
   ```
   - O hash deve ser exatamente:
     `20baaa1c693c889dac980d00073bbfec13462a77cb0e76ed980634e4555f684f`
3. Execute o instalador graficamente (ou silenciosamente com `/VERYSILENT /SUPPRESSMSGBOXES`).
4. Verifique a pasta padrão sugerida:
   `%LOCALAPPDATA%\Programs\CloudOS`
5. Conclua a instalação e confirme a integridade dos atalhos no Menu Iniciar e Desktop.

---

## 2. Inicialização Segura e Verificação de Versão (Build 34)

1. Execute o CloudOS pelo atalho ou via script integrado:
   ```powershell
   pwsh -NoProfile -File scripts/flutter/start-cloudos-v21-integrated.ps1
   ```
2. Abra o aplicativo **Configurações** (pelo dock ou atalho `Win + I`):
   - Navegue até a seção **Sobre o CloudOS**:
     - Confirme que a versão exibida é `21.0.0-rc.1.3 (Release Candidate 1.3)`.
     - Confirme a Build `34` e Protocolo `21`.
     - Verifique o rodapé institucional: `CloudOS Provedor de Shell Autônomo para Windows.`
   - No rodapé do **Menu Iniciar**:
     - Confirme que o nome de usuário é resolvido dinamicamente via ambiente do Windows.

---

## 3. Teste de Correção do Diálogo de Reversão (Timer Exponencial)

1. No aplicativo **Configurações**, acesse **Backup & Redefinição**.
2. Clique no botão **Redefinir Configurações**.
3. Um diálogo modal com contagem regressiva de 5 segundos será exibido:
   - Observe a contagem regressiva uniforme (5... 4... 3... 2... 1...).
   - Cancele o diálogo e abra-o novamente.
   - Abra o Gerenciador de Tarefas do Windows (`taskmgr`) e confirme que não ocorre pico de CPU nem vazamento de threads/timers.

---

## 4. Teste de Sessões Repetidas do Terminal ConPTY (Reaping de Zumbis)

1. Abra o aplicativo **Terminal** no dock.
2. Crie múltiplas abas/sessões alternando entre perfis (`PowerShell`, `CMD`, `WSL`).
3. Digite `exit` ou feche várias abas individualmente.
4. Abra novas abas sucessivamente (mais de 32 no total durante o teste).
5. Confirme que o terminal continua alocando novas sessões normalmente, comprovando que sessões finalizadas são imediatamente recicladas (*pruning* ativo).

---

## 5. Teste de Operações de Arquivos e Integridade Massiva

1. Abra o **Gerenciador de Arquivos (Files)**.
2. Tente criar uma nova pasta ou renomear um arquivo para `CON`, `PRN`, `AUX` ou `NUL`.
   - Confirme a exibição da mensagem de segurança bloqueando nomes de dispositivos DOS.
3. Crie e manipule arquivos com caracteres UTF-8 e acentos (`relatório_março.txt`, `日本語_teste.json`).
4. Confirme que arquivos criados pelo CloudOS são perfeitamente acessíveis no Windows Explorer.

---

## 6. Teste de Proteção contra Encerramento no Gerenciador de Tarefas

1. Abra o **Gerenciador de Tarefas do CloudOS**.
2. Localize `explorer.exe` ou `CloudOS.Supervisor.exe`.
3. Tente clicar em **Finalizar**:
   - Confirme o bloqueio pelo diálogo de segurança com ícone de escudo.

---

## 7. Verificação de Reparo e Integridade Transacional

1. Execute a ferramenta de manutenção para validar a instalação:
   ```powershell
   pwsh -NoProfile -File scripts/installer/CloudOS.Maintenance.ps1 -Action repair -InstallDir "$env:LOCALAPPDATA\Programs\CloudOS"
   ```
2. Confirme que todos os 33 arquivos do pacote têm seus hashes SHA256 aprovados.

---

## 8. Salvaguarda Absoluta GATE 0

Ao final da sessão de testes, execute:
```powershell
pwsh -NoProfile -File scripts/safety/assert-gate0.ps1
```
- A saída deve comprovar que:
  - `effective_shell`: `explorer.exe`
  - `userinit_intact`: `True`
  - `custom_shell_detected`: `False`
  - **READY FOR PERSISTENT SHELL ACTIVATION = NO** (conforme a regra de congelamento pré-QA).
