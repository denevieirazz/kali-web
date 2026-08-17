# CloudOS — Distribuição

Este documento descreve a distribuição existente no Productization Batch 2.5. Ele não declara promoção, release pública, assinatura de produção, validação física ou validação visual.

## Artefatos

O pipeline Windows produz instalador Velopack por usuário e ZIP portátil a partir do mesmo staging versionado. O staging contém Bootstrap, Host, backend empacotado, frontend de produção, runtime Node empacotado, `cloudos-core` Linux/amd64 e metadados de inventário/supply chain.

O staging rejeita diretórios mutáveis de usuário como `data`, `cache`, `logs` e `updates`. O pacote instalado fica separado do estado local resolvido pelo Bootstrap. Logs do Bootstrap ficam sob o estado local em `logs/`. O modo portátil mantém executáveis em `app/` e `runtime/`, com `data-portable/` e `logs/` fora de `app/`.

## Instalador

O instalador é gerado por Velopack 1.2.0 e continua `unsigned-development`.

Os testes automatizados exercitam instalação em caminho com espaços e caminho longo, instalação sobre versão existente, múltiplas execuções, reinstalação, update sobre instalação existente, rollback seguido de nova execução do instalador, ausência de Node/Go globais, execução sob conta local padrão, preservação de dados externos ao app e ausência de `data`, `cache`, `logs` e `updates` dentro de `current/`.

Node é fornecido pelo pacote. Go não é requisito de runtime: `cloudos-core` é compilado antes do empacotamento.

## Canais

A matriz canônica está em `productization/channels.json`. `development` é o único canal utilizável pelo artefato atual. `preview` e `stable` exigem assinatura e origem aprovada; como nenhuma origem oficial foi configurada e o build continua sem Authenticode, esses canais falham fechados.

## Evidência de integridade

A distribuição carrega/publica como evidência `manifest.json`, `components.json`, `checksums.sha256`, `supply-chain.json`, SBOMs, licenças/notices, `artifact-audit.json`, `artifact-security-report.json` e `CloudOSDiagnostics.zip`.

O artifact security gate cruza arquivos reais do staging com manifesto, build result, component inventory, supply chain, hashes e evidência de licença. Inconsistência reprova o pipeline.

## Validador físico

`Validar Distribuição CloudOS.cmd` inicia o gate físico interativo em Windows com PowerShell 7. O wrapper unifica em `validation.json` resultados, referências de screenshots, logs, artefatos, versões, metadados/hash do banco real antes/depois, WSL antes/depois e processos CloudOS antes/depois.

A CI verifica somente o contrato estático do validador. Ela não executa checkpoints físicos ou visuais. Ao terminar uma execução física, o wrapper imprime `explorer "<pasta_resultados>"` e tenta abrir a pasta automaticamente.

## Limites atuais

- distribuição sem assinatura Authenticode;
- nenhuma origem `preview`/`stable` aprovada;
- nenhuma release publicada;
- nenhum gate físico executado por este batch;
- smoke de WSL depende de existir uma distro WSL real na máquina de validação.
