# WORKFLOW PRODUCTIVITY REVIEW — CloudOS Batch 3.6

Escopo: `feature/cloudos-workflow-batch-3`.

Este documento registra apenas comportamento verificável no código e nos testes do Workflow Batch 3.6. Não é validação física, visual, de promoção ou de distribuição. Não mede tempo economizado, cliques economizados ou ganho percentual de produtividade porque não existe baseline reproduzível anexado a este batch.

## O que ainda obriga abrir Windows

- **Pasta Windows arbitrária exige grant explícito.** O Files não atravessa o filesystem do host silenciosamente; o usuário precisa escolher uma pasta pela File System Access API.
- **O grant Windows não entrega ao Terminal um caminho físico confiável.** Por isso `Terminal aqui` continua fail-closed para a origem Windows em vez de inventar um `cwd`.
- **Downloads do Browser nativo congelado não são redirecionados fisicamente pelo destino escolhido no Workflow.** A preferência de destino é exibida e persistida, mas o processo nativo do Browser não foi alterado neste batch.
- **Exportar um Workspace usa o fluxo de download do navegador/WebView.** A escolha final de onde o arquivo exportado fica no host continua sujeita ao comportamento do ambiente que recebe esse download.

## O que ainda obriga abrir Linux diretamente

- **Operações que dependam de ferramentas Linux fora das superfícies já expostas continuam sendo feitas no Terminal.** O Batch 3.6 não adiciona novas ferramentas, WSLg ou runtime de agentes.
- **Linux Files depende do provider WSL existente estar disponível.** O Workflow não instala, modifica ou substitui o WSL Core v2.
- **`Terminal aqui` é realmente resolvido somente para Linux Home.** OPFS não possui caminho de sistema operacional e o grant Windows não expõe um caminho físico confiável ao Terminal.

## O que ainda parece três sistemas diferentes

- **As três origens mantêm semânticas reais diferentes:** OPFS é armazenamento privado do navegador/WebView, Windows depende de autorização explícita e Linux Home usa o provider WSL existente.
- **A lixeira não é idêntica entre providers.** O Files explica a origem e só oferece restauração quando o provider possui metadata/identificador suficiente; ele não finge equivalência com a Lixeira do Windows.
- **Mover entre providers não é atômico.** O fluxo do Workspace cria a nova cópia, valida o processo pela conclusão das operações existentes e depois arquiva a origem. A origem não é apagada automaticamente.
- **Transferência portátil de Workspace é limitada por projeto:** até 2.000 itens, 64 MiB agregados e 16 MiB por arquivo no bundle JSON. Symlinks são rejeitados.
- **Permissões e persistência continuam específicas da origem.** Unificar a interface não altera as garantias reais de cada filesystem.

## O que já parece um sistema único

- **Existe um único CloudOS Files** para OPFS, Windows grant e Linux Home, com origem visível, breadcrumb unificado, seleção contextual, busca da pasta, ações rápidas e atalhos.
- **A política de abertura é única e fail-closed:** `txt`, `md`, `json` e `log` vão para Notes; `png`, `jpg`, `jpeg`, `webp` e `pdf` vão para o Viewer; diretórios navegam; desconhecidos mostram informações; symlinks não são seguidos; executáveis e scripts não são executados.
- **Notes funciona como nota e como editor rápido de arquivo regular.** Arquivos reais têm Salvar, Salvar Como, Fechar, indicador de modificação e proteção contra descarte; não recebem autosave silencioso.
- **A busca de Notes usa conteúdo real carregado**, mostra resultados/destaques e permite saltar entre ocorrências, sem IA ou embeddings.
- **O Viewer é o mesmo para as origens suportadas**, mantendo PDF sandboxed e imagens com zoom, pan, Fit e 1:1.
- **Recentes e Documentos recentes usam um índice local único** de arquivos realmente abertos pelo Files, limitado a 30 entradas.
- **Workspace usa o mesmo modelo em qualquer provider suportado**, com renomear, arquivar, duplicar, exportar, importar e mover com preservação da origem.
- **O destino atual de downloads do Workflow é mostrado de forma permanente** no Workspace e no contexto do Files, junto da limitação explícita do Browser nativo congelado.
- **O Launcher trata WebOnly como capacidade**, mostrando que o Browser CloudOS está disponível apenas no modo Full e oferecendo o navegador padrão sem apresentar um Browser nativo impossível como resultado comum.
- **O Terminal mantém várias sessões dentro da mesma janela**, com criar, alternar, renomear e fechar abas. A implementação não altera o protocolo, o transporte nem o backend do Terminal.

## Medições de produtividade

- Cliques removidos: **não medido**.
- Tempo economizado por fluxo: **não medido**.
- Percentual de produtividade: **não medido**.
- Validação física do Batch 3.6: **não executada por este review**.
- Validação visual física: **não executada por este review**.

O Batch 3.6 não promove, não publica release e não altera a linha Productization RC.
