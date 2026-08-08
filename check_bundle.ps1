$content = Get-Content 'C:\Users\d\Music\projeto\cloudos-frontend\dist\assets\index-CP6ymnME.js' -Raw
# Look near openApp
$idx = 515425
Write-Host $content.Substring([Math]::Max(0,$idx-50), 3000)
