# LEGACY / ADMINISTRATIVE ONLY
#
# This script configures the Windows Shell Launcher (WESL_UserSetting) feature on
# supported Enterprise/Education/IoT editions. It predates the current CloudOS
# activation path and is intentionally kept only for compatibility/experiments.
#
# Current authority:
#   V13 deployment  -> scripts/native/CloudOS.Deployment.V13.psm1
#   V14 activation  -> scripts/native/CloudOS.ShellActivation.V14.psm1
#
# Do not call this script from normal install/update/activation flows. V14 is
# per-user, snapshots the exact prior Winlogon Shell value and has journal/repair
# semantics that this WESL helper does not provide.

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Status', 'Enable', 'Disable')]
    [string]$Action = 'Status',

    [string]$ShellPath = (Join-Path $PSScriptRoot '..\..\desktop\CloudOS.NativeShell\bin\Release\CloudOS.exe'),

    [switch]$DisableProvider
)

$ErrorActionPreference = 'Stop'

function Get-CloudOSCurrentSid {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Assert-CloudOSShellLauncherEdition {
    $caption = (Get-CimInstance Win32_OperatingSystem).Caption
    $supported = $caption -match 'Enterprise|Education|IoT'
    if (-not $supported) {
        throw "Shell Launcher oficial nao e suportado nesta edicao: $caption. Use o CloudOS coexistindo com Explorer."
    }
    return $caption
}

function Get-CloudOSShellLauncherClass {
    try {
        return Get-CimClass -Namespace 'root/standardcimv2/embedded' -ClassName 'WESL_UserSetting'
    }
    catch {
        throw 'WESL_UserSetting nao esta disponivel. Verifique se o recurso Shell Launcher esta instalado/habilitado nesta edicao do Windows.'
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute este script em um PowerShell elevado (Administrador).'
    }
}

$edition = Assert-CloudOSShellLauncherEdition
$class = Get-CloudOSShellLauncherClass
$sid = Get-CloudOSCurrentSid

if ($Action -eq 'Status') {
    $enabled = Invoke-CimMethod -CimClass $class -MethodName 'IsEnabled'
    $custom = $null
    try {
        $custom = Invoke-CimMethod -CimClass $class -MethodName 'GetCustomShell' -Arguments @{ Sid = $sid }
    }
    catch {
        # No custom shell for this SID is a valid state.
    }

    [pscustomobject]@{
        Edition = $edition
        Sid = $sid
        Enabled = [bool]$enabled.Enabled
        Shell = if ($custom -and $custom.Shell) { $custom.Shell } else { '<nao configurado para este usuario>' }
        DefaultAction = if ($custom) { $custom.DefaultAction } else { $null }
    } | Format-List
    return
}

Assert-Administrator

if ($Action -eq 'Enable') {
    $resolvedShell = (Resolve-Path -LiteralPath $ShellPath).Path
    if (-not (Test-Path -LiteralPath $resolvedShell -PathType Leaf)) {
        throw "CloudOS.exe nao encontrado: $resolvedShell"
    }

    $target = "SID $sid -> $resolvedShell"
    if ($PSCmdlet.ShouldProcess($target, 'Configurar CloudOS como Shell Launcher oficial e habilitar o provedor')) {
        $setResult = Invoke-CimMethod -CimClass $class -MethodName 'SetCustomShell' -Arguments @{
            Sid = $sid
            Shell = $resolvedShell
            CustomReturnCodes = $null
            CustomReturnCodesAction = $null
            DefaultAction = 0
        }
        if ($setResult.ReturnValue -ne 0) {
            throw "SetCustomShell retornou $($setResult.ReturnValue)."
        }

        $enableResult = Invoke-CimMethod -CimClass $class -MethodName 'SetEnabled' -Arguments @{ Enabled = $true }
        if ($enableResult.ReturnValue -ne 0) {
            throw "SetEnabled retornou $($enableResult.ReturnValue)."
        }

        Write-Host 'CloudOS configurado como Shell Launcher para o usuario atual.'
        Write-Host 'A configuracao entra em vigor na proxima entrada de sessao. Mantenha um usuario administrador de recuperacao.'
    }
    return
}

if ($Action -eq 'Disable') {
    if ($PSCmdlet.ShouldProcess("SID $sid", 'Remover o shell customizado CloudOS deste usuario')) {
        $removeResult = Invoke-CimMethod -CimClass $class -MethodName 'RemoveCustomShell' -Arguments @{ Sid = $sid }
        if ($removeResult.ReturnValue -ne 0) {
            throw "RemoveCustomShell retornou $($removeResult.ReturnValue)."
        }

        if ($DisableProvider) {
            if ($PSCmdlet.ShouldProcess('Shell Launcher global', 'Desabilitar o provedor Shell Launcher para o dispositivo')) {
                $disableResult = Invoke-CimMethod -CimClass $class -MethodName 'SetEnabled' -Arguments @{ Enabled = $false }
                if ($disableResult.ReturnValue -ne 0) {
                    throw "SetEnabled(false) retornou $($disableResult.ReturnValue)."
                }
            }
        }

        Write-Host 'Configuracao customizada do CloudOS removida para o usuario atual.'
    }
}