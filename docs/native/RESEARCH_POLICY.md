# Política: pesquisar antes de implementar

Esta regra vale para qualquer nova funcionalidade do CloudOS Native.

## Regra obrigatória

Antes de criar ou reescrever um subsistema:

1. pesquisar a API oficial da plataforma;
2. procurar exemplos oficiais e projetos open source maduros que resolvam o mesmo problema;
3. verificar a licença antes de copiar/adaptar código;
4. preferir reutilizar APIs nativas e componentes comprovados em vez de reconstruir tudo do zero;
5. registrar a pesquisa e a decisão em `docs/native/research/`;
6. só então implementar;
7. validar build, CI e comportamento real.

## Prioridade de fontes

1. Microsoft Learn / Windows SDK / Windows classic samples;
2. documentação oficial do componente ou protocolo;
3. projetos C++/Win32 maduros e ativos;
4. implementações em outras tecnologias apenas como referência de UX/contrato.

## Licenças

- MIT/BSD/Apache e equivalentes: código pode ser adaptado se os avisos/licença forem preservados conforme exigido.
- GPL/AGPL e licenças incompatíveis: usar somente como referência de arquitetura/UX, sem copiar código.
- licença desconhecida: não copiar.
- licença declarada de forma inconsistente no próprio projeto: tratar como referência apenas até a divergência ser esclarecida.

## Restrições do CloudOS

Pesquisa e reaproveitamento não podem reintroduzir como runtime do shell:

- WebView/WebView2;
- Chromium/Electron;
- React/Vite/HTML/CSS;
- captura de janela como modelo de composição;
- `SetParent` para fingir que aplicativos Windows externos são filhos do CloudOS.

Aplicativos Windows continuam HWNDs top-level reais.

## Formato mínimo de uma nota de pesquisa

Cada nota deve responder:

- qual problema estava sendo resolvido;
- quais fontes foram consultadas;
- o que foi reutilizado;
- o que foi apenas inspiração;
- qual licença foi verificada;
- por que a solução escolhida respeita a arquitetura do CloudOS;
- quais fallbacks existem.
