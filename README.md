# CloudOS Patch 01

Substitui somente os dois arquivos de produção e adiciona um teste.

Arquivos:
- backend/src/config/index.js
- backend/src/database/index.js
- backend/test/persistence.test.js

O agente deve copiar exatamente estes arquivos sobre o workspace, sem outras alterações, e executar `npm.cmd test`, `npm.cmd run lint` e `npm.cmd run build` na raiz.
