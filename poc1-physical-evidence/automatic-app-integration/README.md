# Evidência física de containment

Execute os coletores em PowerShell 7 a partir da raiz do repositório. A fase
`During` exige o JSON de baseline; qualquer coleta incompleta ou violação
termina com código diferente de zero.

## 0. Descoberta automática de um aplicativo não previsto

L3afpad foi instalado pelo `apt`, sem entrada manual ou catálogo curado. O
coletor força uma nova varredura XDG, correlaciona o pacote instalado com seu
arquivo `.desktop` e registra `Name`, `Exec`, `Icon`, `Categories` e
`MimeType`:

```powershell
node scripts/collect-app-discovery-evidence.mjs `
  --distribution Ubuntu `
  --app L3afpad `
  --package l3afpad `
  --output poc1-physical-evidence/automatic-app-integration/app-discovery-l3afpad.json
```

O JSON comprova ID opaco estável, `source=linux`, lançamento
`xpra-contained`, metadados pesquisáveis e ausência de `Exec`/caminho no
contrato público.

## 1. Baseline Win32 antes de abrir o aplicativo Linux

```powershell
pwsh -NoProfile -File scripts/collect-windows-window-evidence.ps1 `
  -Phase Baseline `
  -TargetMarkers l3afpad,firefox `
  -OutputDirectory poc1-physical-evidence/automatic-app-integration `
  -Prefix windows-hwnd-baseline
```

## 2. Sessão Linux contida já aberta pelo CloudOS

Use o display retornado pela API de sessão. O nome do servidor é
`cloudos-poc1-<session.id>`; por exemplo, para uma sessão com id
`xpra-abc123` use `cloudos-poc1-xpra-abc123`.

```powershell
node scripts/collect-linux-containment-evidence.mjs `
  --distribution Ubuntu `
  --display 101 `
  --session-name cloudos-poc1-xpra-SESSION_ID `
  --app l3afpad `
  --output-dir poc1-physical-evidence/automatic-app-integration `
  --prefix linux-containment-l3afpad
```

O coletor usa `wsl.exe --system -u root` somente para inspeção. Ele correlaciona
display e session-name antes de entrar no namespace do PID e comprova:

- árvore Xpra -> Xvfb/Xorg -> aplicativo;
- UIDs não-root e namespaces privados de mount/PID;
- `DISPLAY=:N`, `GDK_BACKEND=x11` e `QT_QPA_PLATFORM=xcb`;
- ausência de Wayland, Pulse, WSL interop e segredo Xpra no ambiente do app;
- máscaras de `/mnt/wslg`, `/run/WSL` e `/init`;
- ausência do socket X0 do WSLg, inclusive abstrato;
- socket Xpra de filesystem em `/run/xpra` privado e listener TCP autenticado
  por segredo efêmero; a superfície só é publicada ao renderer por capability
  opaca no proxy local do CloudOS.

## 3. HWND e Alt+Tab durante a sessão

```powershell
pwsh -NoProfile -File scripts/collect-windows-window-evidence.ps1 `
  -Phase During `
  -TargetMarkers l3afpad,firefox `
  -BaselineJson poc1-physical-evidence/automatic-app-integration/windows-hwnd-baseline.json `
  -OutputDirectory poc1-physical-evidence/automatic-app-integration `
  -Prefix windows-hwnd-during
```

O relatório separa HWNDs invisíveis de infraestrutura do WSLg de uma janela
RAIL externa: exige zero HWND do aplicativo, zero novo RAIL visível e zero
candidato externo no Alt+Tab. Títulos de outras janelas são omitidos e
representados apenas por SHA-256.

Arquivos `.json` são a evidência estruturada; arquivos `.log` são o resumo
humano. Só um relatório com `Verdict: PASS` e exit code `0` pode sustentar
`CONTAINMENT PASS`.

## 4. Capturas verificadas

- `cloudos-unified-start-menu-l3afpad.png`: menu Iniciar com contagens Windows,
  Linux e Todos, categorias e o L3afpad detectado pelo scanner.
- `cloudos-l3afpad-contained-window.png`: L3afpad renderizado na surface Xpra
  dentro da janela CloudOS.

Os relatórios `linux-containment-cloudos-l3afpad.*` e
`windows-hwnd-during-cloudos-l3afpad.*` foram coletados enquanto a segunda
captura estava visível. Eles provam a cadeia de processos/display e zero HWND,
Alt+Tab ou janela RAIL externa do aplicativo.
