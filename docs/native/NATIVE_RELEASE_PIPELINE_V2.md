# CloudOS Native Release Pipeline V2

Este documento descreve o fluxo autoritativo de desenvolvimento, build, verificacao e distribuicao do CloudOS Native Shell.

## Autoridade do shell

O Desktop, Start, Taskbar, Window Manager, Snap Assist, recovery, notificacoes e superficies principais do CloudOS sao C++/Win32 nativos. O frontend React antigo permanece no repositorio como referencia visual e historico de migracao; ele nao e compilado nem copiado para o release nativo. Microsoft WebView2 continua permitido somente no Navegador CloudOS in-process.

## Um unico build para desenvolvedor e CI

O ponto de entrada e:

```cmd
scripts\native\build-cloudos-native.cmd Release
```

O mesmo comando e executado no GitHub Actions. Isso evita o problema de o CI testar uma sequencia diferente da usada no PC de desenvolvimento.

O build executa, nesta ordem:

1. contratos estaticos do shell e WebSkin;
2. contratos de produtividade de Start/Taskbar;
3. contratos do pipeline de release;
4. restore do SDK WebView2 somente se o pacote ainda nao estiver presente;
5. build do CloudOS.NativeRuntime x64;
6. build do CloudOS.NativeShell x64;
7. remocao de qualquer `bin\Release\ui` legado;
8. geracao do manifesto de proveniencia;
9. validacao SHA256 dos binarios e do fingerprint das fontes.

## Fingerprint deterministico das fontes

`scripts/native/get-native-build-fingerprint.ps1` percorre as fontes que realmente afetam o shell:

- `desktop/CloudOS.NativeRuntime`;
- `desktop/CloudOS.NativeShell`;
- `scripts/native`.

`bin`, `obj`, `packages` e `.vs` sao excluidos. Cada arquivo recebe SHA256, a lista e ordenada e o conjunto inteiro recebe um SHA256 final.

Isso resolve dois problemas do modelo anterior baseado apenas em `git rev-parse HEAD`:

- alteracoes locais nao commitadas agora invalidam corretamente o build;
- depois que exatamente essas alteracoes locais forem compiladas, abrir novamente o CloudOS nao recompila infinitamente.

O fingerprint compilado fica em:

```text
desktop/CloudOS.NativeShell/bin/Release/.cloudos-build-fingerprint
```

## Manifesto de proveniencia

Cada build valido produz:

```text
desktop/CloudOS.NativeShell/bin/Release/cloudos-native-manifest.json
```

O manifesto registra:

- schema do formato;
- produto;
- autoridade `C++/Win32`;
- configuracao e plataforma;
- horario UTC;
- commit Git quando disponivel;
- fingerprint SHA256 das fontes;
- tamanho e SHA256 de `CloudOS.exe`;
- tamanho e SHA256 de `CloudOS.NativeRuntime.dll`;
- declaracao explicita de que o desktop React legado nao faz parte do release.

## Startup verificado

O launcher autoritativo e:

```cmd
Iniciar CloudOS Nativo.cmd
```

Ele encaminha argumentos para `scripts/native/start-cloudos-native.cmd`.

Antes de iniciar, o launcher:

1. confirma EXE, DLL, manifesto e fingerprint;
2. recalcula o fingerprint das fontes atuais;
3. compara com o fingerprint compilado;
4. verifica tamanho e SHA256 dos binarios contra o manifesto;
5. rejeita a existencia de `bin\Release\ui` legado;
6. recompila automaticamente se qualquer verificacao falhar;
7. encerra uma instancia antiga antes do linker substituir `CloudOS.exe`;
8. valida novamente o build depois da compilacao;
9. so entao inicia o shell.

### Flags

Forcar build completo:

```cmd
"Iniciar CloudOS Nativo.cmd" --force-rebuild
```

Validar e iniciar sem permitir build automatico:

```cmd
"Iniciar CloudOS Nativo.cmd" --no-build
```

`/force` e `/nobuild` sao aliases.

## Diagnostico em um comando

Execute:

```cmd
"Verificar CloudOS Nativo.cmd"
```

ou diretamente:

```powershell
./scripts/native/get-native-build-status.ps1
```

O diagnostico mostra HEAD, fingerprint atual, fingerprint compilado, estado do manifesto, integridade SHA256 e se o build esta pronto para executar.

Para integracao com ferramentas:

```powershell
./scripts/native/get-native-build-status.ps1 -Json
```

## Pacote portatil

O empacotador e:

```powershell
./scripts/native/package-cloudos-native.ps1 -Configuration Release
```

Ele verifica o build antes de empacotar e produz:

```text
desktop/CloudOS.NativeShell/artifacts/CloudOS-Native-Release-x64.zip
```

O ZIP contem:

- `CloudOS.exe`;
- `CloudOS.NativeRuntime.dll`;
- `cloudos-native-manifest.json`;
- `.cloudos-build-head` quando Git estiver disponivel;
- `.cloudos-build-fingerprint`;
- `SHA256SUMS.txt`;
- `Iniciar CloudOS.cmd`;
- `LEIA-ME.txt`.

## GitHub Actions

Cada push da branch `rewrite/cloudos-native-full-system`:

1. usa o mesmo build entrypoint do PC;
2. verifica o manifesto e o grafo compilado;
3. cria o ZIP portatil;
4. calcula SHA256 do ZIP;
5. publica `CloudOS-Native-Release-x64-<commit>` como artifact por 14 dias.

O artifact nao inclui o desktop React antigo.

## Quick-access hub

O botao de energia/acesso rapido do Start agora funciona como um launcher hierarquico amplo, separado por grupos:

- CloudOS e desenvolvimento: Browser, Arquivos, Drive, Projetos e VS Code;
- Terminais: CMD, PowerShell e WSL/Kali;
- Produtividade: Executar, Calculadora, Bloco de Notas, Paint, Captura, Midia e Clima;
- Ferramentas do sistema: Monitor, Task Manager, Device Manager, Registro, disco do sistema e Apps;
- Sistema e configuracoes: CloudOS/Windows Settings, tela, som, rede, Wi-Fi, Bluetooth, armazenamento, clipboard, data/hora, Developer Settings, Windows Security, Windows Update e Saude do Sistema;
- sessao e energia: lock, restart/exit CloudOS e restart/shutdown Windows.

## Regra de regressao

Os contratos em `scripts/native/test-native-release-pipeline-contract.ps1` e `scripts/native/test-taskbar-productivity-contract.ps1` devem falhar se qualquer uma dessas garantias for removida silenciosamente.
