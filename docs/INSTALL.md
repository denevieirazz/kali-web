# Guia de Instalação do CloudOS (Release Candidate 1.1)

O instalador oficial do CloudOS é gerado via Inno Setup 6 e foi projetado para execução segura em modo de usuário (*per-user*), sem exigir privilégios de Administrador (UAC) para o fluxo padrão.

---

## 1. Requisitos de Sistema

- **Sistema Operacional:** Windows 10 (Build 19041 / versão 2004 ou superior) ou Windows 11 (64 bits).
- **Arquitetura:** `x64` (AMD64 / Intel 64).
- **Memória RAM:** Mínimo de 4 GB (recomendado 8 GB ou superior).
- **Espaço em Disco:** 250 MB livres.
- **Dependências Nativas do Windows:**
  - Visual C++ 2015–2022 Redistributable (x64)
  - Microsoft Edge WebView2 Runtime (Evergreen)
  - *Opcional:* WSL2 (Windows Subsystem for Linux) para recursos de terminal Linux. O CloudOS funciona perfeitamente sem o WSL ativado.

---

## 2. Instalação Padrão (Interface Gráfica)

1. Baixe o pacote oficial: `CloudOS-Setup-21.0.0-rc.1.2-x64.exe`.
2. Verifique o checksum SHA256 com o arquivo `SHA256SUMS.txt`.
3. Dê duplo clique no executável.
4. Escolha o idioma (Português Brasileiro ou Inglês).
5. O instalador validará automaticamente os requisitos de sistema. Se alguma dependência opcional não for encontrada, uma mensagem informativa será exibida sem bloquear a instalação.
6. O diretório padrão de instalação é `%LOCALAPPDATA%\Programs\CloudOS`.
7. Conclua o assistente e inicie o CloudOS.

---

## 3. Instalação Silenciosa (Linha de Comando)

Para ambientes de automação ou instalação automatizada, use os parâmetros padrão do Inno Setup:

```cmd
CloudOS-Setup-21.0.0-rc.1.2-x64.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

Parâmetros adicionais suportados:
- `/DIR="C:\MeuCaminho\CloudOS"`: Especifica um diretório alternativo de instalação (com proteção contra instalação na raiz ou diretórios do Windows).
- `/TASKS="desktopicon"`: Cria o atalho na Área de Trabalho.

---

## 4. Reparo da Instalação

Se algum arquivo executável ou biblioteca for corrompido ou excluído acidentalmente:

1. Execute o script de manutenção fornecido no diretório do produto:
   ```powershell
   pwsh.exe -NoProfile -File scripts\installer\CloudOS.Maintenance.ps1 -Action repair
   ```
2. Ou execute novamente o instalador `CloudOS-Setup-21.0.0-rc.1.2-x64.exe`, que substituirá os arquivos defeituosos preservando as preferências e dados do usuário.

---

## 5. Desinstalação Limpa

O CloudOS oferece desinstalação segura e completa através de:
- **Painel de Controle / Configurações do Windows:** Aplicativos e Recursos -> Localize "CloudOS" -> Desinstalar.
- **Via executável do produto:** Executar `%LOCALAPPDATA%\Programs\CloudOS\unins000.exe`.
- **Via script de manutenção:**
   ```powershell
   pwsh.exe -NoProfile -File scripts\installer\CloudOS.Maintenance.ps1 -Action uninstall
   ```

> [!IMPORTANT]
> A desinstalação garante estritamente:
> - O shell oficial do Windows (`explorer.exe`) permanece o shell ativo e intocado.
> - As chaves `HKCU\Run` e atalhos de inicialização são removidos.
> - Os arquivos temporários e logs de instalação são limpos.
> - Suas preferências em `%LOCALAPPDATA%\CloudOS` são preservadas a menos que `-PurgeUserData` seja fornecido explicitamente.
