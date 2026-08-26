# CloudOS Bootstrap

`CloudOS.Bootstrap` é um guardião de recuperação por usuário, independente de
WebView2 e Node.js. Ele inicia somente `CloudOS.Host.exe`, valida por named pipe um
handshake emitido depois que o bundle React monta, vinculado ao PID iniciado, e
observa sua saída. Uma navegação HTTP bem-sucedida, sozinha, não marca prontidão.

Três falhas em dois minutos interrompem o reinício automático e apresentam uma
janela WPF com três ações: tentar novamente uma vez, abrir o log no Bloco de Notas
e sair. Depois de 90 segundos estáveis, o contador de falhas é zerado. O estado
atômico fica em `%LOCALAPPDATA%\CloudOS\bootstrap-state.json` e os logs em
`%LOCALAPPDATA%\CloudOS\logs`.

Este componente não altera o Registro, não substitui o shell do Windows, não inicia
Explorer e não executa comandos recebidos da interface web. Ele é infraestrutura
preparatória e ainda não é usado pelos scripts normais do CloudOS.

A opção interna `--preview`, usada apenas por `npm run preview:shell`, permite que
o usuário feche uma prévia antes dos 90 segundos sem registrar um crash. Uma futura
ativação real não usa essa opção: até uma saída com código zero conta como falha se
o shell não completar o período mínimo de estabilidade.

Exemplo de desenvolvimento:

```powershell
dotnet run --project desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj -- --host C:\caminho\CloudOS.Host.exe --root C:\caminho\CloudOS-Unified --fullscreen
```

Testes puros da política e do journal:

```powershell
dotnet run --project desktop/CloudOS.Bootstrap.Tests/CloudOS.Bootstrap.Tests.csproj -c Release
```
