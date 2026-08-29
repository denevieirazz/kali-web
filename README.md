# CloudOS Native

CloudOS agora e um shell de desktop nativo para Windows x64. O caminho de execucao do produto nao depende de React, Vite, Node, WebView2, HTML/CSS/JavaScript, C# ou XAML.

## Runtime

O produto e formado por dois componentes C++:

- `desktop/CloudOS.NativeShell` -> `CloudOS.exe`, shell Win32 visivel.
- `desktop/CloudOS.NativeRuntime` -> `CloudOS.NativeRuntime.dll`, primitivas de processo, Job Objects, ConPTY, WSL e eventos de HWND.

O shell usa Win32, DWM, Direct2D/DirectWrite, Common Controls, ConPTY, Toolhelp/PSAPI, SetWinEventHook e APIs nativas de WSL onde disponiveis.

## O que ja funciona

- desktop e taskbar nativos;
- menu Iniciar nativo;
- descoberta e gerenciamento de HWNDs reais;
- 4 workspaces;
- tiling por monitor em layout master/stack;
- snap, foco, minimizar, maximizar, fechar e floating;
- terminal visivel ConPTY;
- terminal WSL/Kali;
- navegador de arquivos Windows e `\\wsl.localhost`/`\\wsl$`;
- catalogo e lancamento de aplicativos Windows;
- gerenciador de processos;
- dialogo Executar;
- hotkeys globais;
- DPI per-monitor-v2;
- Job Objects kill-on-close no runtime de processos;
- restauracao das janelas ocultadas por workspace durante shutdown do shell.

Aplicativos Windows continuam sendo janelas top-level reais. CloudOS gerencia posicionamento, foco, workspace, tiling, taskbar e lifecycle em volta delas; nao existe mais a exigencia de encaixar todo programa dentro de um navegador ou WebView.

## Hotkeys

Todas usam `Ctrl+Alt`, exceto mover uma janela entre workspaces, que usa tambem `Shift`.

- `Enter`: terminal nativo.
- `K`: WSL/Kali.
- `E`: Arquivos.
- `A`: Aplicativos.
- `P`: Processos.
- `R`: Executar.
- `T`: liga/desliga tiling.
- `F`: liga/desliga floating da janela ativa.
- `J` / `H`: proxima/anterior janela.
- `Q`: fecha a janela ativa.
- `M`: minimiza.
- `Z`: maximiza/restaura.
- `Setas`: snap da janela ativa.
- `1` a `4`: troca de workspace.
- `Shift+1` a `Shift+4`: move a janela ativa para o workspace escolhido.
- `X`: encerra o CloudOS.

## Compilar e iniciar

Requisitos de desenvolvimento:

- Windows 10/11 x64;
- Visual Studio 2022 Build Tools ou Visual Studio com `Desktop development with C++`;
- MSVC v143;
- Windows 10/11 SDK.

Use:

```text
Compilar CloudOS.cmd
Iniciar CloudOS.cmd
Validar CloudOS.cmd
Empacotar CloudOS.cmd
```

`Iniciar CloudOS.cmd` compila Release e abre `CloudOS.exe`.

## Distribuicao

O CI `CloudOS Native Windows CI` compila o runtime e o shell em Windows x64, verifica a fronteira nativa, valida `CloudOS.exe` + `CloudOS.NativeRuntime.dll` e publica o artefato `CloudOS-Native-x64`.

O pacote portatil contem somente os binarios necessarios e metadados de build. WSL e Kali continuam sendo capacidades opcionais do Windows; quando nao estiverem instalados, o restante do shell continua utilizavel.

## Regra arquitetural

Nao adicionar uma camada web de volta ao caminho de boot. Qualquer UI de sistema nova deve ser Win32/DirectX/Windows API ou outra tecnologia nativa que preserve acesso direto ao Windows.
