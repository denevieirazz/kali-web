# CloudOS V21 — Preview vs Integrado

## Regra de autoridade

O Flutter V21 nao substitui a autoridade nativa do desktop.

- `CloudOS.exe` (C++/Win32) continua sendo a autoridade do NativeShell.
- `CloudOS.Supervisor.exe` continua sendo a autoridade de recovery/readiness.
- `CloudOS.SystemBroker.exe` continua sendo a boundary tipada para operacoes de sistema.
- `cloudos_flutter_shell.exe` e a camada de apresentacao companion integrada.
- Browser, Terminal e workspace continuam pertencendo ao NativeShell.

## Modo Preview

Use `Abrir CloudOS Flutter Preview.cmd` quando a intencao for apenas desenvolver ou inspecionar a apresentacao Flutter.

Esse modo nao promete lifecycle real das superficies nativas, workspace real nem runtime integrado. Preview pode operar com fixtures/fallbacks onde os contratos ja permitem isso.

## Modo Integrado

Use `Abrir CloudOS V21 Flutter com System Broker.cmd` ou `Iniciar CloudOS V21 Integrado.cmd` do artifact da CI.

O launcher integrado:

1. valida o manifesto nativo;
2. valida SHA256 de `CloudOS.exe`, `CloudOS.NativeRuntime.dll`, `CloudOS.Supervisor.exe`, `CloudOS.SystemBroker.exe` e `CloudOS.BrokerProbe.exe`;
3. valida o manifesto composto `cloudos-v21-integrated-manifest.json` e o SHA256 do executavel Flutter;
4. inicia o NativeShell por `CloudOS.Supervisor.exe` quando a autoridade ainda nao esta ativa;
5. espera o endpoint tipado `CloudOS.NativeShell.Activation.v21`;
6. rejeita uma autoridade ativa cuja imagem nao seja o `CloudOS.exe` do mesmo bundle;
7. inicia o System Broker e exige `BrokerProbe ping` com sucesso;
8. inicia a apresentacao Flutter somente depois dessas boundaries estarem prontas.

O launcher integrado nao altera Winlogon e nao ativa CloudOS como shell de logon. Shell Activation V14 permanece um fluxo opt-in separado.

## Integridade em camadas

`cloudos-native-manifest.json` assina os cinco componentes nativos do runtime V21.

`cloudos-v21-integrated-manifest.json` compoe essa autoridade com a apresentacao Flutter, armazenando:

- SHA256 do manifesto nativo;
- SHA256 de `cloudos_flutter_shell.exe`;
- autoridade C++/Win32;
- recovery Supervisor V11;
- Broker V21;
- modo `native-authority-with-flutter-presentation`.

Assim, o manifesto integrado nao duplica a lista de hashes nativos: ele referencia a cadeia nativa autoritativa e adiciona somente a camada Flutter.

## Gate de artifact

O workflow `CloudOS Flutter UI` compila o runtime nativo pelo developer entrypoint, monta a apresentacao Flutter, compoe os dois manifests, executa o verificador integrado e somente depois cria o ZIP V21.
