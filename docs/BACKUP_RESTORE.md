# CloudOS — Backup e Restore

## O que entra no backup

`backup-cloudos.ps1` cria um ZIP explícito contendo somente dados selecionados do diretório local do CloudOS.

Diretórios de primeiro nível aceitos:

- `data`
- `settings`
- `workspaces`
- `preferences`
- `app-state`

Arquivos de estado aceitos na raiz:

- `bootstrap-state.json`
- `prerequisites-v1.json`
- `distribution-state.json`

Logs, caches, runtime, updates, backups, `node_modules`, resultados de teste e nomes com aparência de segredo/credencial/chave/token são excluídos.

O ZIP contém:

- `manifest.json` com versão do produto, HEAD, inventário, tamanho e SHA-256 dos arquivos;
- `checksums.sha256` cobrindo o payload;
- `payload/` com os arquivos selecionados.

## Restore

Use `restore-cloudos.ps1` com `-ConfirmRestore`. O restore valida completamente archive, manifesto, checksums, payload, compatibilidade, espaço e escrita antes de começar a substituir arquivos.

O commit é transacional por arquivo: conteúdo anterior é movido para rollback temporário antes da cópia. Uma falha restaura o estado anterior e não cria o marker final de sessão.

## Compatibilidade

O restore aceita somente backup `CloudOS`, schema 1 e a mesma versão major do produto configurado. Backups de major diferente são rejeitados antes da alteração do destino.

## Sessões

Uma sessão backend ativa é motivo de recusa. Depois de restore completo, `restore-session-invalidated.marker` sinaliza que sessões anteriores devem ser consideradas inválidas.

## CI

Há dois níveis automatizados:

- `test-backup-restore.ps1`: contrato normal de backup/restore;
- `test-recovery-hardening.ps1`: matriz negativa e preservação dos dados anteriores.

Nenhum desses testes usa o banco real do usuário.
