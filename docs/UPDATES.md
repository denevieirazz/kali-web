# CloudOS — Atualizações

Este documento descreve somente o updater existente no Productization Batch 2.5.

## Motor

O CloudOS usa Velopack 1.2.0 para descobrir, baixar, validar e aplicar pacotes gerenciados. O modo portátil não usa atualização automática: sua substituição continua manual.

O fluxo normal é:

1. carregar `meta/product.json` e `meta/channels.json`;
2. validar canal, transição e origem;
3. consultar o feed com downgrade desabilitado;
4. exigir metadados de pacote com nome, tamanho e SHA-256 válidos;
5. baixar pelo Velopack, que valida a integridade do pacote;
6. registrar `PreviousVersion`, `PendingVersion`, source e canal em `distribution-state.json`;
7. aplicar e reiniciar;
8. somente após o Host atingir o período de estabilidade, marcar a versão/canal como saudáveis.

Enquanto existe versão pendente, o estado anterior permanece identificado para recuperação explícita.

## Canais

A matriz canônica está em `productization/channels.json` e é empacotada como `meta/channels.json`.

Transições permitidas neste lote:

- `development -> development`
- `development -> preview`
- `preview -> preview`
- `preview -> stable`
- `stable -> stable`

Mudança de canal é rejeitada quando não foi pedida explicitamente. Transições reversas ou saltos não declarados são rejeitados.

### development

Aceita o fluxo experimental atual. Fonte local é permitida. HTTP só é aceito para fixture loopback quando `CLOUDOS_ALLOW_LOCAL_UPDATE_FIXTURE=1`; feed remoto normal continua exigindo HTTPS.

### preview e stable

Exigem assinatura de distribuição. O Batch 2.5 continua `unsigned-development`, portanto esses canais permanecem fail-closed. Nenhuma origem oficial foi inventada: `approvedOrigins` está vazio até existir uma origem real e aprovada.

`stable` também continua sujeito a `stableUpdatesEnabled=false` no metadata atual.

## Downgrade e rollback

O check normal usa `AllowVersionDowngrade=false` e também possui uma verificação explícita de direção de versão.

Downgrade só é aceito pelo caminho de recuperação que solicita uma versão específica conhecida. Esse caminho é separado do update normal e não torna downgrade silencioso possível.

## Integridade e falhas

Os testes do lote cobrem pacote adulterado, hash divergente, pacote truncado/parcial, cancelamento de download e fixtures sequenciais. A atualização não é preparada quando a validação falha.

O teste Windows também cobre aplicação sem reinício seguida de rollback, falha deliberada de health do runtime empacotado seguida de rollback, e atualização sequencial para uma terceira versão, preservando dados em diretório separado.

## Assinatura

Authenticode ainda não está provisionado. Isso é uma limitação deliberada e impede preview/stable. Este documento não declara assinatura nem publicação de release.
