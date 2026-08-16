# Scripts CloudOS

## Organização alvo

- `scripts/launch/` — launcher e lifecycle de processos.
- `scripts/diagnostics/` — coleta/resumo de ambiente e sessões.
- `scripts/validate/` — gates reproduzíveis e orquestração de validação.

Scripts históricos permanecem onde estão durante o Batch 1 para evitar migração destrutiva. Wrappers novos devem apontar explicitamente para a implementação canônica.

## Entradas de usuário

Na raiz:

- `Iniciar CloudOS.cmd [Full|WebOnly|Developer|UXValidation|FilesValidation|BrowserValidation|TerminalValidation]`
- `Diagnosticar CloudOS.cmd`
- `Parar CloudOS.cmd`
- `Validar CloudOS.cmd [smoke|full|terminal|files|browser|onboarding|system-center|launcher]`

## Regras

- nunca instalar ferramentas globais silenciosamente;
- dependências npm são preparadas de modo idempotente a partir da raiz do workspace;
- stdout/stderr de filhos são capturados desde o spawn;
- não esperar timeout quando o processo já encerrou;
- logs de falha não são apagados automaticamente;
- validações usam dados temporários e não alteram o banco real;
- scripts não promovem/mesclam branches.
