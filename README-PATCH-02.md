# CloudOS Patch 02 - Launcher

Extraia na raiz do CloudOS-Unified e aceite mesclar a pasta `scripts`.

Depois, use dois cliques em `Iniciar CloudOS.cmd`.

Logs ficam em `logs/`. Para encerrar manualmente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-cloudos.ps1
```
