# CloudOS RC1.1 — Checklist de Prontidão para Lançamento

Este documento lista todas as verificações exigidas para certificar a estabilidade e integridade do Release Candidate 1.1 (`21.0.0-rc.1.1`).

---

## 1. Segurança e Gate 0

- [x] **HKLM Winlogon Shell:** Inalterado (`explorer.exe`).
- [x] **Userinit:** Padrão e intacto (`C:\WINDOWS\system32\userinit.exe,`).
- [x] **HKCU Shell:** Vazio / não configurado.
- [x] **Windows Explorer:** Em execução ininterrupta.
- [x] **Validação Automatizada:** `scripts/safety/assert-gate0.ps1` executado e aprovado.
- [x] **Contenção Modo Usuário:** Zero drivers de kernel, zero serviços privilegiados globais.

---

## 2. Compilação e Engenharia de Release

- [x] **Centralização de Versão:** `version.json` atualizado para `21.0.0-rc.1.1` (build 32).
- [x] **Flutter Shell Version:** `CloudOSVersion` expõe os metadados de versão unificados em `cloudos_version.dart`.
- [x] **Settings Window:** Identificação dinâmica de versão e Git SHA sem strings obsoletas.
- [x] **Pipeline Reproduzível:** `scripts/release/build-rc.ps1` implementado e funcional.
- [x] **Compilação C++:** 5 executáveis e DLLs nativas compilados em Release x64.
- [x] **Compilação Flutter:** `flutter build windows --release` concluído com sucesso.
- [x] **Instalador Oficial:** Inno Setup 6 compilou `CloudOS-Setup-21.0.0-rc.1.1-x64.exe`.
- [x] **Checksums e Manifestos:** `SHA256SUMS.txt`, manifesto canônico e `.sha256` gerados.

---

## 3. Resiliência de Preferências e Atualizações

- [x] **Migração de Schema v1 -> v2:** Clamping de coordenadas, validação de temas e modos de visualização.
- [x] **Quarentena de Corrupção:** Arquivos JSON inválidos são isolados em `.corrupt.<timestamp>`.
- [x] **Rotação de Backups:** Limite rígido de até 5 backups rotativos (`preferences.backup.1..5.json`).
- [x] **Updater com Staging Atômico:** Validado com fail-closed e rollback automático se o health check falhar.
- [x] **Downgrade Protection:** Bloqueio de instalação de builds mais antigas sem a flag `-Force`.
- [x] **Feed de Atualizações:** Modelo padronizado `update-feed.json`.

---

## 4. Salvaguardas e Casos de Borda

- [x] **Task Manager Denylist:** Processos vitais do Windows e serviços core (`CloudOS.Supervisor.exe`, `CloudOS.SystemBroker.exe`) protegidos contra encerramento.
- [x] **Filesystem Guards:** Bloqueio de exclusão em `C:\Windows`, `C:\Program Files` e raízes de disco.
- [x] **Validação de Nomes:** Bloqueio de nomes de dispositivos DOS (`CON`, `PRN`, etc.) e caracteres proibidos.
- [x] **Pacote de Diagnóstico:** `export-diagnostics-bundle.ps1` gera suporte sanitizado em `.zip`.

---

## 5. Suítes de Testes

- [x] `flutter analyze`: 0 problemas.
- [x] `flutter test`: 156/156 testes aprovados (151 prévios + 5 da suíte de preferências).
- [x] Suíte de contratos nativos: 49/49 contratos aprovados.
- [x] Suíte de contratos de instalador: 5/5 contratos aprovados.
- [x] Suíte de contratos de startup: 5/5 contratos aprovados.
- [x] Suíte de contratos de shell: 10/10 contratos aprovados.
- [x] Auto-teste do System Broker: 51/51 asserções aprovadas.
