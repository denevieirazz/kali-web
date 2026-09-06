# CloudOS — Guia de Testes do Usuário (RC1)

Este guia orienta a validação prática e interativa do CloudOS Release Candidate 1 (RC1) em ambiente de execução real.

---

## 1. Como Iniciar o CloudOS RC1

Execute o script de inicialização segura em modo janela a partir da raiz do projeto:

```powershell
pwsh -NoProfile -File scripts/flutter/start-cloudos-v21-integrated.ps1
```

Ou execute o binário empacotado da distribuição:

```powershell
.\dist\CloudOS\CloudOS.exe
```

---

## 2. Roteiro de Verificação Funcional

### A. Primeira Execução (OOBE)
1. Ao iniciar em perfil limpo, observe o assistente de boas-vindas com 7 etapas rápidas (< 1 min).
2. Verifique a detecção automática do perfil de hardware (Econômico, Balanceado ou Alto Desempenho).
3. Conclua o assistente e certifique-se de que a preferência é gravada.

### B. Desktop e Ícones
1. Arraste qualquer ícone da Área de Trabalho para uma nova posição.
2. Feche e reabra o CloudOS: confirme que as coordenadas foram persistidas.
3. Redimensione a janela do CloudOS para um tamanho menor: observe o reflow e clamp automático (os ícones não saem da área visível).

### C. Menu Iniciar e Busca Profunda
1. Clique no botão Iniciar na Taskbar ou pressione a tecla Windows / atalho configurado.
2. Digite "resolução", "áudio", "energia" ou "downloads": verifique a exibição dos resultados de busca profunda (*Deep Search*).
3. Clique com o botão direito em um aplicativo fixado: selecione "Desafixar do Início".
4. Abra um aplicativo e volte ao Iniciar: confirme sua presença na seção "Recentes".

### D. Gerenciador de Arquivos e Lixeira
1. Abra o aplicativo **Arquivos (Files)**.
2. Na barra lateral esquerda, clique em **Lixeira**.
3. Observe a exibição da `RecycleBinView` com o total de itens e tamanho ocupado na lixeira do Windows.
4. Clique em **Esvaziar Lixeira**: verifique o diálogo de confirmação seguro.

### E. Gerenciador de Tarefas
1. Abra o **Gerenciador de Tarefas**.
2. Ordene por consumo de CPU e Memória.
3. Localize um processo de sistema (ex: `explorer.exe` ou `dwm.exe`) e tente finalizar: verifique o bloqueio de segurança que impede a finalização acidental.

### F. Terminal ConPTY
1. Abra o **Terminal**.
2. Clique no ícone `+` no cabeçalho das abas: alterne entre **PowerShell**, **CMD** e **WSL**.
3. Em uma aba, digite `exit`: confirme a exibição do banner de processo encerrado e o botão **Reiniciar Sessão**.

### G. Central de Configurações
1. Abra as **Configurações**.
2. Verifique a seção **Visão Geral** com os cartões informativos de Tela, Som, Rede, Bateria/Energia, WSL e Shell.
3. Acesse **Sobre** > **Preferências e Backup do Usuário**: clique em **Exportar Configurações (JSON)**.

---

## 3. Verificação de Integridade e Gate 0

Em qualquer momento durante ou após os testes, verifique que o Windows Explorer permanece como shell oficial:

```powershell
.\dist\CloudOS\CloudOS.Recovery.exe status
```

A saída deve confirmar:
- `status`: `"EXPLORER"`
- `effective_shell`: `"explorer.exe"`
- `userinit_intact`: `true`
- `explorer_running`: `true`
