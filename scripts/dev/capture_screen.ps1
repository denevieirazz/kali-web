Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap ($screen.Width, $screen.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
$artifactDir = 'C:\Users\dougl\.gemini\antigravity\brain\e0ea3935-20e3-4f15-a2a8-79266b2d4907'
$outPath = Join-Path $artifactDir 'cloudos_v21_etapa2_screenshot.png'
$bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
Write-Host "SCREENSHOT_SAVED: $outPath"
