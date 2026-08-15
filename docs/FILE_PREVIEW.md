# CloudOS File Preview & OPFS Hardening

Branch: `feature/cloudos-file-preview`

Esta feature melhora o CloudOS Files sem alterar o backend, banco de autenticação, Host, WSL ou filesystem real do Windows.

## Preview seguro

O painel de preview suporta formatos com limites explícitos:

- texto/código: 2 MB;
- imagens raster: 25 MB;
- PDF: 50 MB;
- áudio: 100 MB;
- vídeo: 150 MB.

Formatos desconhecidos falham fechado. SVG é tratado como texto e nunca renderizado como imagem ativa dentro do Shell privilegiado. Texto usa `<pre>` e não `dangerouslySetInnerHTML`. PDF usa URL `blob:` local em `iframe` com `sandbox=""`. Imagem/áudio/vídeo usam object URLs temporárias revogadas no cleanup.

Arquivos de até 25 MB também recebem SHA-256 local via Web Crypto para inspeção de integridade. O hash não é persistido automaticamente.

## Lixeira

A Lixeira OPFS agora mantém metadados separados em `.cloudos-trash-meta.json`:

- caminho original;
- nome original;
- data da exclusão;
- tipo do item.

Ao restaurar, o Files tenta devolver o item ao diretório original. Se esse diretório não existir mais, restaura na raiz `local:`. Colisões recebem nome único em vez de sobrescrever dados.

A metadata fica dentro da área OPFS da própria feature; nenhuma informação é enviada ao backend.

## Operações de arquivo

As operações OPFS foram extraídas de `CloudOSFiles.tsx` para `opfsFileService.ts`. O componente React fica responsável por estado e interface.

Correções:

- bloqueio de copiar/mover uma pasta para dentro dela própria ou de um descendente;
- recortar e colar no mesmo diretório vira no-op seguro;
- upload pode selecionar novamente o mesmo arquivo porque o input é limpo após a operação;
- leituras assíncronas de diretório/preview usam generation guards para evitar resultado antigo sobrescrever estado atual;
- URLs temporárias de download/preview são revogadas;
- restauração da Lixeira respeita a origem real;
- ações destrutivas continuam pedindo confirmação na interface.

## UX

- painel lateral de preview;
- preview de propriedades;
- drag and drop para upload;
- edição rápida de texto limitada a 2 MB;
- download da seleção;
- pesquisa e ordenação existentes preservadas;
- atalhos: Enter abre, F2 renomeia, Delete exclui, Ctrl+C/X/V copia/recorta/cola, Esc fecha a seleção/preview;
- layout responsivo: em janelas estreitas o preview vira painel sobreposto.

## Testes

`frontend/test/filePreviewPolicy.test.js` cobre:

- classificação de texto/imagem/PDF/áudio/vídeo;
- SVG tratado como texto;
- limites de tamanho;
- binários desconhecidos bloqueados;
- tentativa de copiar pasta para ela própria/descendente;
- cópia para diretório irmão;
- recorte no mesmo diretório.

A CI da branch roda lint, build, backend/integration, E2E, frontend unit, Host build/tests e `git diff --check` contra `integration/cloudos-foundation`.

## Limitações

- preview não é editor completo de imagem/PDF/mídia;
- restauração de itens antigos existentes na Lixeira antes desta feature pode não possuir caminho original e, nesse caso, volta para a raiz;
- OPFS não substitui ainda um mount do NTFS/WSL; essa integração deve ser feita por broker/Host próprio em uma fase posterior;
- diretórios grandes ainda são enumerados integralmente; indexação/virtualização é uma etapa futura.
