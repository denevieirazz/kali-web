# CloudOS Virtual Disk — desenho futuro

Status: **design somente**. O Stabilization Batch 1 não cria, formata, monta, redimensiona ou anexa VHD/VHDX.

## Por que separar este tema do Files atual

O CloudOS possui três conceitos de armazenamento diferentes:

1. **Armazenamento local do navegador (OPFS)** — privado do origin e controlado pelo motor do navegador/WebView; não é partição, HD ou VHDX.
2. **Pasta Windows autorizada** — grant explícito a uma árvore escolhida pelo usuário; não representa acesso ao disco inteiro.
3. **Linux Home** — filesystem POSIX dentro da distribuição WSL, acessado pelo WSL Core sob uma raiz confinada.

Uma quota lógica do CloudOS limita uso de um workspace; ela **não aloca espaço físico nem cria um disco**.

## Opção futura A — VHDX gerenciado pelo Windows

Possível arquitetura:

```text
CloudOS Host privilegiado
  -> broker allowlisted de storage
  -> CreateVirtualDisk/OpenVirtualDisk
  -> AttachVirtualDisk
  -> inicialização/particionamento somente após consentimento explícito
  -> ACL dedicada ao usuário/serviço CloudOS
```

Riscos:

- operações podem exigir elevação;
- montagem incorreta pode expor ou corromper volumes;
- resize/compact/repair têm requisitos diferentes;
- lifecycle precisa recovery após crash/reboot;
- agentes nunca devem receber acesso direto às APIs de disco;
- testes físicos devem ser feitos primeiro em VM/snapshot descartável.

## Opção futura B — VHDX usado pelo WSL

WSL já usa VHDX internamente em vários cenários, porém o CloudOS não deve manipular arquivos internos de distribuição nem assumir formato/layout privado. Um volume próprio só deve ser considerado com APIs e lifecycle documentados, sem editar `.wslconfig`, importar distro ou alterar a distro do usuário silenciosamente.

## Opção futura C — quota lógica sem disco virtual

Para muitos workspaces, quota lógica por provider é suficiente e muito menos privilegiada. Pode registrar:

- provider;
- raiz;
- limite lógico;
- uso observado;
- política de retenção;
- capability de leitura/escrita.

Esse é o modelo recomendado antes de introduzir VHDX real.

## Gate para implementação futura

Antes de qualquer código de VHD/VHDX:

1. ameaça/modelo de privilégio;
2. broker nativo com allowlist estrita;
3. confirmação explícita de create/attach/delete/resize;
4. proteção contra caminho arbitrário e mount point arbitrário;
5. recovery/watchdog após crash;
6. testes em VM descartável;
7. logs/auditoria sem segredos;
8. aprovação física do proprietário.
