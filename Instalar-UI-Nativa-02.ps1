$ErrorActionPreference='Stop';$Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$Main=Join-Path $Root 'frontend\src\main.tsx';$Start=Join-Path $Root 'frontend\src\components\StartMenu\StartMenu.tsx';$StartCss=Join-Path $Root 'frontend\src\components\StartMenu\StartMenu.css';$Desktop=Join-Path $Root 'frontend\src\components\Desktop\Desktop.tsx';$Index=Join-Path $Root 'frontend\index.html'
if(-not(Test-Path $Main)-or-not(Test-Path $Start)-or-not(Test-Path $Desktop)){throw 'Execute na raiz do CloudOS-Unified.'}
$Stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$Backup=Join-Path $Root "backup-native-ui02-$Stamp";New-Item -ItemType Directory -Force $Backup|Out-Null
foreach($rel in @('frontend\src\main.tsx','frontend\src\components\StartMenu\StartMenu.tsx','frontend\src\components\StartMenu\StartMenu.css','frontend\src\components\Desktop\Desktop.tsx','frontend\index.html')){$s=Join-Path $Root $rel;if(Test-Path $s){$d=Join-Path $Backup $rel;New-Item -ItemType Directory -Force (Split-Path $d)|Out-Null;Copy-Item $s $d -Force}}
Copy-Item (Join-Path $Root 'payload\frontend\src\components\StartMenu\StartMenu.tsx') $Start -Force
Copy-Item (Join-Path $Root 'payload\frontend\src\components\StartMenu\StartMenu.native.css') (Join-Path (Split-Path $Start) 'StartMenu.native.css') -Force
$st=Get-Content $Start -Raw;$st=$st-replace "import './StartMenu.css';","import './StartMenu.css';`r`nimport './StartMenu.native.css';";Set-Content $Start $st -Encoding UTF8
$Native=Join-Path $Root 'frontend\src\native';New-Item -ItemType Directory -Force $Native|Out-Null;Copy-Item (Join-Path $Root 'payload\frontend\src\native\themeSync.ts') (Join-Path $Native 'themeSync.ts') -Force;Copy-Item (Join-Path $Root 'payload\frontend\src\native\responsiveShell.css') (Join-Path $Native 'responsiveShell.css') -Force
$m=Get-Content $Main -Raw;if($m-notmatch "native/themeSync"){$m="import './native/themeSync';`r`nimport './native/responsiveShell.css';`r`n"+$m};Set-Content $Main $m -Encoding UTF8
$d=Get-Content $Desktop -Raw
$d=$d-replace "const GRID = 88;","const GRID = 88;"
$d=$d-replace "\{ id: 'refresh', label: 'Atualizar', shortcut: 'F5', onClick: \(\) => window\.location\.reload\(\) \}","{ id: 'refresh', label: 'Atualizar', shortcut: 'F5', onClick: () => { setIcons(prev => [...prev]); setSelectedIcons(new Set()); } }"
$marker='  // ── Rubber band selection ──────────────────────────────────────────────────'
$resize=@'
  // Reorganiza os ícones quando a área útil muda, sem depender do zoom do navegador.
  useEffect(() => {
    const desktop = desktopRef.current;
    if (!desktop) return;
    let lastWidth = 0; let lastHeight = 0;
    const observer = new ResizeObserver(([entry]) => {
      const width = Math.floor(entry.contentRect.width); const height = Math.floor(entry.contentRect.height);
      if (width === lastWidth && height === lastHeight) return; lastWidth = width; lastHeight = height;
      const usableHeight = Math.max(GRID, height - 12); const rows = Math.max(1, Math.floor(usableHeight / GRID));
      setIcons(previous => previous.map((icon, index) => ({ ...icon, x: 12 + Math.floor(index / rows) * GRID, y: 12 + (index % rows) * GRID })));
    });
    observer.observe(desktop); return () => observer.disconnect();
  }, []);
'@
if($d-notmatch 'Reorganiza os ícones quando a área útil muda'){$d=$d-replace [regex]::Escape($marker),($resize+$marker)}
Set-Content $Desktop $d -Encoding UTF8
$i=Get-Content $Index -Raw;$i=[regex]::Replace($i,'(?im)^.*cloudos-start-menu\.js.*(\r?\n)?','');Set-Content $Index $i -Encoding UTF8
Push-Location $Root
try{& npm.cmd run lint;if($LASTEXITCODE){throw 'Lint falhou'};& npm.cmd run build;if($LASTEXITCODE){throw 'Build falhou'};& npm.cmd test;if($LASTEXITCODE){throw 'Testes falharam'};Write-Host "UI nativa instalada. Backup: $Backup" -ForegroundColor Green}catch{Write-Host 'Falha. Restaurando backup...' -ForegroundColor Red;foreach($rel in @('frontend\src\main.tsx','frontend\src\components\StartMenu\StartMenu.tsx','frontend\src\components\StartMenu\StartMenu.css','frontend\src\components\Desktop\Desktop.tsx','frontend\index.html')){$s=Join-Path $Backup $rel;if(Test-Path $s){$dest=Join-Path $Root $rel;Copy-Item $s $dest -Force}};throw}finally{Pop-Location}
