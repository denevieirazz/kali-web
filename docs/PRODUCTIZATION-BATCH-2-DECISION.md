# CloudOS Productization Batch 2 — decisão de distribuição

Data da decisão: 2026-08-16
Base: `ffaa9fd302065fbfd7c7123896d19465c1cd3e8a`
Branch: `productization/cloudos-distribution-batch-2`
Status: experimental / unsigned-development

## Decisão

O Batch 2 usa **Velopack 1.2.0** como empacotador/instalador/updater principal no Windows x64 e mantém um **ZIP portátil independente** como segundo formato de distribuição.

A integração Velopack pertence ao `CloudOS.Bootstrap`, que já é o guardião do ciclo de vida, crash-loop e recuperação do `CloudOS.Host`. O `CloudOS.Host` continua responsável pelo WebView2, frontend e backend nativo supervisionado. Não haverá segundo updater dentro do Host.

O instalador experimental será por usuário em `%LocalAppData%`, sem requisito administrativo, com atalho no Menu Iniciar. O pacote continuará explicitamente não assinado neste lote. Nenhuma release real será publicada.

## Comparação

| Opção | Vantagens | Limitações para o CloudOS | Decisão |
|---|---|---|---|
| Velopack 1.2.0 | setup por usuário sem UAC; atalhos; updater; canais; pacotes full/delta; portable; integração C#; instalação estável em LocalAppData | exige integração correta no entrypoint e disciplina de feed/hash; assinatura continua externa | **Principal** |
| MSIX | identidade de pacote; instalação/remoção limpa; separação de estado; distribuição corporativa | assinatura confiável é requisito para implantação; containerização e virtualização adicionam atrito para app desktop misto com processos filhos, Node e integração WSL | Não adotado no Batch 2 |
| WiX/MSI | Windows Installer maduro; forte controle corporativo; per-user/per-machine | maior custo de autoria/manutenção; updater/rollback do produto teria de ser composto; não agrega valor suficiente ao fluxo experimental | Reserva futura; Velopack pode gerar MSI, mas não será o formato primário |
| ZIP portátil | zero instalação; fácil inspeção; ótimo para recuperação/teste | sem Add/Remove Programs; sem atualização/atalhos automáticos | **Formato secundário obrigatório** |

## Versões e toolchain fixados

- Velopack NuGet: `1.2.0`.
- `vpk`: `1.2.0`, instalado em diretório local de build; nunca ferramenta global flutuante.
- Node distribuído: `22.23.2` x64, obtido da distribuição oficial e validado contra `SHASUMS256.txt`.
- .NET: publicação `win-x64` self-contained para Bootstrap e Host; a máquina final não depende de .NET global.
- WebView2 SDK do Host: permanece na versão já fixada no projeto; runtime Evergreen é pré-requisito diagnosticado, não instalado automaticamente neste lote.
- Go: `cloudos-core` é compilado para Linux x64 e incluído como payload para uso somente quando o WSL existente estiver apto.

## Layout do pacote

```text
CloudOS/
  CloudOS.Bootstrap.exe
  app/
    host/CloudOS.Host.exe
  agent/
    backend/...
  web/
    index.html
    assets/...
  runtime/
    node.exe
    node-runtime/*
    cloudos-core
  meta/
    product.json
    manifest.json
    components.json
    checksums.sha256
    SBOM/
    licenses/
```

Dados mutáveis permanecem fora da árvore versionada de binários:

```text
%LocalAppData%\CloudOS\data
%LocalAppData%\CloudOS\logs
%LocalAppData%\CloudOS\cache
%LocalAppData%\CloudOS\updates
%LocalAppData%\CloudOS\runtime
%TEMP%\CloudOS\...
```

O modo portátil usa `data-portable/` e `logs/` dentro da própria pasta portátil e deve definir os caminhos de dados explicitamente, sem reutilizar os dados da instalação.

## Backend e frontend

O frontend distribuído é somente `frontend/dist`, gerado em modo production. Vite dev-server não faz parte de nenhum artefato.

O backend continua JavaScript Node, mas o pacote inclui um runtime Node x64 fixado. O `CloudOS.Host` já procura `runtime/node.exe` e já reconhece o layout empacotado `agent/backend` + `web`. Portanto a máquina final não precisa de Node global.

O staging copia somente os arquivos de produção necessários ao backend e as dependências npm de produção resolvidas pelo lockfile da raiz. `node_modules` nunca é copiado como árvore de desenvolvimento inteira; o staging monta uma árvore de runtime dedicada e auditada.

## WebView2

O modo escolhido é Evergreen. O Bootstrap/central de pré-requisitos verifica disponibilidade e versão e oferece orientação ao usuário se estiver ausente. Não baixa nem instala WebView2 automaticamente neste lote.

## Atualizações

Canais:

- `development`: artefatos/feed locais de teste;
- `preview`: feed HTTPS/teste explicitamente configurado;
- `stable`: desabilitado neste lote.

O updater valida canal, versão e hash antes de disponibilizar aplicação. Download fica em cache temporário e pode ser cancelado. Aplicação exige reinício e nunca deve ocorrer durante sessão marcada como crítica. Downgrade silencioso é rejeitado.

O Batch 2 usa fixture local para testar atualização. GitHub Releases é somente destino futuro; nenhuma release é criada/publicada por CI.

## Rollback e recuperação

O Bootstrap mantém a responsabilidade de recuperação. O estado de distribuição registra versão atual, versão anterior conhecida, atualização pendente e confirmação de primeiro boot saudável. Falha de health após atualização preserva logs e oferece restauração dos binários anteriores. Dados do usuário não fazem parte do rollback binário.

## Backup/restauração

Backup explícito inclui apenas dados CloudOS conhecidos e um manifesto com versão/SHA/checksums. Caches, logs, `node_modules`, Windows grants externos, Linux Home e conteúdo grande não consentido ficam de fora.

Restauração valida o ZIP, compatibilidade e checksums, cria backup de segurança e só então substitui dados. Falha restaura o backup de segurança.

## Desinstalação

O padrão seguro é remover aplicação e preservar dados/backups. WSL, Kali, Linux Home, grants Windows, WebView2, PowerShell, .NET global e Node global nunca são alvos do desinstalador do CloudOS.

## Supply chain

Todo pacote gera SHA-256, inventário, SBOM e licenças detectáveis. O estado de assinatura deste lote é sempre `unsigned-development`. CI falha se encontrar bancos, segredos, logs, `test-results`, caches ou source tree inesperada no staging.

## WSL Containers

WSL Containers/`wslc` está em public preview e a documentação atual orienta uso de WSL pré-release para experimentação. O Batch 2 **não depende dessa API**, não executa `wsl --update --pre-release` e não modifica a instalação WSL. É apenas uma opção futura a reavaliar quando houver API estável.

## Fontes primárias consultadas

- Velopack docs: https://docs.velopack.io/getting-started/csharp
- Velopack packaging: https://docs.velopack.io/packaging/overview
- Velopack Windows: https://docs.velopack.io/packaging/operating-systems/windows
- Velopack installer: https://docs.velopack.io/packaging/installer
- Velopack shortcuts: https://docs.velopack.io/integrating/shortcuts
- Velopack release 1.2.0: https://github.com/velopack/velopack/releases/tag/1.2.0
- MSIX containerization: https://learn.microsoft.com/windows/msix/msix-containerization-overview
- MSIX signing: https://learn.microsoft.com/windows/msix/package/signing-package-overview
- WiX Package scope: https://docs.firegiant.com/wix/schema/wxs/package/
- .NET publishing: https://learn.microsoft.com/dotnet/core/deploying/
- WebView2 distribution: https://learn.microsoft.com/microsoft-edge/webview2/concepts/distribution
- SignTool: https://learn.microsoft.com/windows/win32/seccrypto/signtool
- GitHub Releases: https://docs.github.com/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- Node 22 distribution: https://nodejs.org/download/release/latest-v22.x/
- WSL Containers preview: https://devblogs.microsoft.com/commandline/wsl-container-is-now-available-for-public-preview/
