# CloudOS RC1.1 — Roteiro de Testes de Aceitação do Usuário (User QA Script)

Este roteiro permite a validação manual e visual das melhorias introduzidas no Release Candidate 1.1.

---

## Cenário 1: Instalação Limpa via Assistente Gráfico

1. Execute o instalador `dist\releases\21.0.0-rc.1.1\CloudOS-Setup-21.0.0-rc.1.1-x64.exe`.
2. Observe que o assistente abre em Português Brasileiro com design moderno.
3. Clique em Avançar e selecione a pasta de instalação padrão (`%LOCALAPPDATA%\Programs\CloudOS`).
4. Tente selecionar `C:\Windows` ou `C:\` como destino.
   - **Resultado esperado:** O instalador exibe mensagem de bloqueio impedindo a instalação nessas pastas protegidas.
5. Conclua a instalação no diretório padrão e marque a opção para iniciar o CloudOS.
   - **Resultado esperado:** O CloudOS inicia diretamente na Área de Trabalho com todos os serviços nativos ativos.

---

## Cenário 2: Verificação de Versão e Diagnósticos

1. Abra o menu Iniciar ou o atalho na Barra de Tarefas e selecione **Configurações**.
2. Navegue até a seção **Diagnósticos**:
   - Verifique que a versão reportada é `21.0.0-rc.1.1 (Release Candidate 1.1)`.
   - Verifique que o Git SHA exibido corresponde ao commit atual.
3. Clique no botão **Copiar Diagnóstico Sanitizado**.
   - **Resultado esperado:** Uma notificação confirma a cópia. Cole no Bloco de Notas e verifique que nenhum caminho absoluto ou segredo foi incluído.
4. Navegue até a seção **Sobre o CloudOS**:
   - Verifique o texto "Versão 21.0.0-rc.1.1 • Release Candidate 1.1 (Build 32)".

---

## Cenário 3: Proteção de Processos Críticos no Gerenciador de Tarefas

1. Abra o **Gerenciador de Tarefas** do CloudOS.
2. Localize um processo do sistema (ex: `explorer.exe` ou `dwm.exe`).
3. Clique no botão **Finalizar**.
   - **Resultado esperado:** Um diálogo modal "Processo Protegido" impede a finalização e explica o motivo de segurança.
4. O mesmo bloqueio ocorre se tentar finalizar `CloudOS.Supervisor.exe` ou `CloudOS.SystemBroker.exe`.

---

## Cenário 4: Validação de Nomes e Exclusão no Gerenciador de Arquivos

1. Abra o aplicativo **Arquivos**.
2. Clique em **Nova Pasta** e digite `CON` ou `AUX` ou um nome terminando com espaço/ponto (ex: `teste. `).
   - **Resultado esperado:** Uma mensagem de erro em vermelho avisa que a palavra é reservada do Windows ou o formato é inválido.
3. Digite um nome válido (ex: `Documentos de Trabalho`).
   - **Resultado esperado:** A pasta é criada com sucesso.
4. Tente excluir itens em `C:\Windows`.
   - **Resultado esperado:** A operação é cancelada com alerta de proteção de diretórios do sistema.

---

## Cenário 5: Resiliência de Preferências e Quarentena

1. Feche o CloudOS.
2. Abra o arquivo `%LOCALAPPDATA%\CloudOS\preferences-v1.json` e insira caracteres inválidos para corromper a sintaxe JSON.
3. Inicie o CloudOS novamente.
   - **Resultado esperado:** O CloudOS abre normalmente usando as configurações padrão seguras, e o arquivo corrompido é renomeado automaticamente para `preferences-v1.json.corrupt.<timestamp>`.
