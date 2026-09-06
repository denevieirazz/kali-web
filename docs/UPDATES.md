# CloudOS — Pipeline de Atualizações Atômicas e Rollback (RC1.1)

O CloudOS adota um mecanismo de atualização atômico com validação prévia (*fail-closed*), proteção contra *downgrade* não intencional e capacidade de reversão imediata (*rollback*) sem corromper a instalação em execução.

---

## 1. Fluxo de Atualização Atômica

1. **Validação do Pacote (Staging Pré-Commit):**
   - O pacote de atualização contém o manifesto canônico `cloudos-package-manifest.json` com tamanho e hash SHA256 de todos os arquivos.
   - O updater valida **100%** dos arquivos antes de modificar qualquer arquivo da instalação ativa.
   - Se qualquer arquivo estiver corrompido, faltante ou com hash divergente, o update é abortado (`UPDATE_REJECTED`) com zero impacto.

2. **Compatibilidade de Versão e Protocolo:**
   - O updater compara `protocolVersion` entre a versão atual e a nova versão. Alterações de versão maior no protocolo IPC exigem migração explícita.
   - **Downgrade Protection:** O updater recusa downgrades de build inferiores à build atualmente instalada, a menos que o parâmetro `-Force` seja especificado.

3. **Backup Atômico (`.previous/`):**
   - Antes da substituição de arquivos, a instalação corrente é movida para a pasta `.previous/`.
   - Os novos arquivos são movidos da área temporária de `.staging/` para o diretório raiz do programa.

4. **Health-Check Obrigatório:**
   - Imediatamente após a substituição de arquivos, o updater inicia o `CloudOS.SystemBroker.exe` em modo de teste e executa o `CloudOS.BrokerProbe.exe ping` via Named Pipe.
   - Se o Broker responder `"pong": true` dentro do tempo limite (padrão 15 segundos), o health-check é aprovado.
   - **Rollback Automático:** Se o health-check falhar, o updater restaura imediatamente os arquivos de `.previous/`, retornando a instalação ao estado estável anterior.

---

## 2. Formato do Feed de Atualizações (`update-feed.json`)

O CloudOS suporta distribuição de metadados de novas releases através de um feed JSON estruturado:

```json
{
  "schema": 1,
  "product": "CloudOS",
  "channel": "rc",
  "updatedAt": "2026-09-05T22:00:00Z",
  "releases": [
    {
      "version": "21.0.0-rc.1.3",
      "build": 34,
      "releaseDate": "2026-09-06T01:50:14Z",
      "channel": "rc",
      "minWindowsBuild": 19041,
      "installerFileName": "CloudOS-Setup-21.0.0-rc.1.3-x64.exe",
      "installerUrl": "https://github.com/doug-cloud/CloudOS/releases/download/v21.0.0-rc.1.3/CloudOS-Setup-21.0.0-rc.1.3-x64.exe",
      "sha256": "20baaa1c693c889dac980d00073bbfec13462a77cb0e76ed980634e4555f684f",
      "mandatory": false,
      "releaseNotes": "CloudOS Release Candidate 1.3: Freeze, soak, repeat and resource leak hardening pass."
    }
  ]
}
```

---

## 3. Reversão Manual (Rollback)

Se for necessário desfazer uma atualização após a conclusão do health-check:

```powershell
pwsh.exe -NoProfile -File scripts\installer\CloudOS.Maintenance.ps1 -Action rollback -InstallDir "$env:LOCALAPPDATA\Programs\CloudOS"
```

O comando restaura o conteúdo preservado em `.previous/` e revalida a integridade do manifesto.
