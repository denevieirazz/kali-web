# CloudOS — Recuperação

A recuperação de dados do Productization Batch 2.5 usa `scripts/productization/restore-cloudos.ps1`. Ela não instala WSL, não altera banco real e não substitui o rollback de versão do Velopack.

## Contrato de restore

O restore exige confirmação explícita e recusa execução quando encontra sessão backend ativa no diretório de runtime.

Antes de alterar o destino, o script:

1. abre e valida a estrutura do ZIP;
2. rejeita excesso de entradas, tamanho total excessivo, paths absolutos, `..` e entradas duplicadas;
3. exige `manifest.json` e `checksums.sha256`;
4. extrai para diretório temporário novo;
5. valida JSON, schema, produto e compatibilidade de versão major;
6. exige cobertura exata entre manifesto, checksums e payload;
7. valida tamanho e SHA-256 de cada arquivo;
8. verifica espaço livre e capacidade de escrita no destino.

Somente depois começa o commit de arquivos.

## Fail closed e rollback

Durante o commit, arquivos existentes são movidos para uma área temporária de rollback antes de serem substituídos. Se qualquer cópia falhar ou o restore for interrompido, arquivos novos são removidos e os anteriores voltam em ordem reversa.

O marker `restore-session-invalidated.marker` só é criado depois que todo o payload foi aplicado.

Falhas em archive, manifest, checksum, espaço, permissão ou extração ocorrem antes do commit e não modificam os dados anteriores.

## Testes negativos automatizados

`test-recovery-hardening.ps1` cobre:

- payload corrompido;
- ZIP truncado;
- checksum inválido;
- manifesto inválido;
- versão major incompatível;
- JSON inválido;
- ZIP inválido;
- extração interrompida/parcial;
- restore interrompido durante o commit;
- espaço insuficiente;
- escrita negada.

Os fault hooks de espaço, permissão e interrupção só são considerados quando `NODE_ENV=test`; eles existem para tornar a falha determinística na CI e não fazem parte do fluxo normal do produto.

O sucesso do conjunto é marcado por `PRODUCTIZATION_RECOVERY_HARDENING_OK`.

## Limites

Este lote não declara recuperação física validada. Falhas reais causadas por antivírus, mídia defeituosa, desligamento abrupto do computador ou ACLs específicas do equipamento ainda pertencem ao gate físico.
