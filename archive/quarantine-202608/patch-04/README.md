# Patch 04 (histórico)

Status: **arquivado / não executar**.

Estes instaladores pertenciam ao Start Menu baseado em manipulação direta do DOM. O runtime atual usa o componente React em `frontend/src/components/StartMenu/StartMenu.tsx`; o script legado não era carregado e seu CSS dependia de uma classe que apenas esse script adicionava.

Os arquivos foram preservados somente como evidência histórica. Os payloads duplicados foram removidos do produto ativo.
