# Auditoria de Distribuição — Productization Batch 2

Este documento descreve o gate automatizado de artefatos do CloudOS na branch `productization/cloudos-distribution-batch-2`. Ele complementa, mas não substitui, o gate físico de distribuição.

## Objetivo

Os artefatos experimentais só são considerados automatizadamente auditados quando o staging, o pacote Velopack e o portátil passam por política de conteúdo, inventário e integridade. O gate não publica release, não promove canal, não altera WSL e não utiliza banco real.

## Evidências geradas

O empacotamento produz:

- `meta/manifest.json`: inventário SHA-256 do staging;
- `meta/checksums.sha256`: checksums do staging;
- `meta/components.json`: componentes empacotados com origem e evidência;
- `meta/supply-chain.json`: proveniência consolidada, inventários e estado de assinatura;
- `meta/SBOM/`: inventários npm CycloneDX, NuGet e módulos Go;
- `meta/portable-manifest.json`: inventário específico do layout relocacionado do portátil;
- `meta/portable-checksums.sha256`: checksums específicos do portátil;
- `artifacts/audit/artifact-audit.json`: resultado final da auditoria, hashes dos artefatos e contagens.

## Política de conteúdo

`scripts/productization/artifact-audit-lib.ps1` rejeita conteúdo que não pertence à distribuição, incluindo `node_modules`, árvores do repositório/testes, fontes Go e diretórios de fonte conhecidos. Também rejeita arquivos de alta sensibilidade por nome/extensão e procura padrões de segredo de alta confiança em arquivos textuais pequenos.

O backend empacotado em `agent/backend/src/server.js` é intencionalmente permitido: trata-se do bundle de runtime do produto, não da árvore `backend/` do repositório.

## Integridade

`scripts/productization/audit-artifacts.ps1` exige cobertura exata dos manifests/checksums, recalcula SHA-256 e verifica identidade de HEAD, versão, canal, RID e estado de assinatura. O portátil é extraído em diretório temporário para validar o layout efetivamente distribuído.

O instalador `Setup.exe`, o pacote `*-full.nupkg` e o ZIP portátil recebem SHA-256 no relatório de auditoria. O `.nupkg` e o ZIP também são inspecionados internamente pela mesma política de conteúdo.

## Supply chain e SBOM

Cada componente de primeiro nível deve declarar `origin` e `evidence`. O supply chain referencia os inventários de npm, NuGet e Go, o runtime oficial do Node, WebView2 e Velopack. Componentes sem origem/evidência explícita fazem o gate falhar.

A assinatura continua deliberadamente `unsigned-development`; assinatura Authenticode é trabalho futuro e não deve ser simulada como concluída.

## CI

A CI Linux executa os testes negativos da política sem precisar gerar artefatos Windows. A CI Windows prepara, compila, empacota, valida layout/supply chain e executa a auditoria sobre os artefatos reais antes do upload do artifact de CI.

## Relação com o gate físico

`Validar Distribuição CloudOS.cmd` continua sendo necessário para confirmar comportamento visual e integração física no Windows. Aprovação automatizada deste documento não autoriza promoção, merge, release ou publicação em canal estável.
