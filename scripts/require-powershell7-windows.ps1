$requiredPowerShellVersion = [Version]'7.2'
$currentPowerShellVersion = $PSVersionTable.PSVersion
$currentPowerShellEdition = if ($PSVersionTable.ContainsKey('PSEdition')) {
    [string]$PSVersionTable['PSEdition']
} else {
    'Desktop'
}

if ($currentPowerShellEdition -ne 'Core' -or $currentPowerShellVersion -lt $requiredPowerShellVersion) {
    $detectedRuntime = if ($currentPowerShellEdition -eq 'Desktop') {
        "Windows PowerShell $($currentPowerShellVersion.ToString())"
    } else {
        "PowerShell $($currentPowerShellVersion.ToString()) ($currentPowerShellEdition)"
    }

    throw "POWERSHELL_7_REQUIRED: o validador nativo do CloudOS exige PowerShell 7.2 ou superior. Detectado: $detectedRuntime. Execute este script com pwsh.exe."
}

if (-not $IsWindows) {
    throw 'WINDOWS_REQUIRED: este validador exige Windows com WebView2 Runtime.'
}
