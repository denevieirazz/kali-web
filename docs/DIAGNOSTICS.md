# CloudOS — Diagnóstico de Distribuição

O Productization Batch 2.5 fornece um export único chamado `CloudOSDiagnostics.zip`, gerado por `scripts/productization/export-diagnostics.ps1` com allowlist explícita. Ele não copia recursivamente o diretório local do usuário.

## Conteúdo

O ZIP inclui `manifest.json`, `components.json`, `checksums.sha256`, `version.json` com versão/HEAD/canal/RID/assinatura, `runtime-inventory.json`, `probes.json`, `supply-chain.json`, `artifact-audit.json`, `artifact-security-report.json` quando já produzido, `logs-inventory.json` e `logs/` com logs recentes selecionados e sanitizados.

## Privacidade e segurança

O export não inclui `cloudos.json` ou outro banco real, `data/` do usuário, grants de Files ou arquivos `.env`.

Linhas de log passam por redaction para padrões de `password`, `token`, `secret`, `api key`, recovery code, grants, Authorization Bearer e JWT. O payload final é verificado novamente e a exportação falha se um padrão sensível conhecido permanecer.

A sanitização é uma defesa adicional; o ZIP continua limitado à allowlist do script e não é um canal para dados arbitrários.

## Testes

`test-diagnostics.ps1` cria um ambiente sintético com banco privado, grant privado e log contendo senha, token, bearer/JWT e grant. O teste exige metadados permitidos, ausência de banco/grants e remoção dos valores secretos sintéticos.

No Windows CI, depois do empacotamento, artifact audit e artifact security gate, o export real é criado em `artifacts/diagnostics/CloudOSDiagnostics.zip` e enviado como evidência da execução.

Nenhum diagnóstico deste batch constitui validação física ou visual.
