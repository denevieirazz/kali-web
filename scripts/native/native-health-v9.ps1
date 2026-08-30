$ErrorActionPreference = 'Stop'

if (-not ('CloudOSHealthNativeV9' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CloudOSHealthNativeV9 {
    [DllImport("kernel32.dll")]
    public static extern ulong GetTickCount64();
}
'@
}

$script:CloudOSHealthMappingNameV9 = 'Local\CloudOS.NativeShell.Health.v9'
$script:CloudOSReadyEventNameV9 = 'Local\CloudOS.NativeShell.Ready.v9'
$script:CloudOSHealthMagicV9 = [uint32]0x39484F43
$script:CloudOSHealthSchemaV9 = [uint32]9
$script:CloudOSHealthStructureSizeV9 = 96

function Get-CloudOSHealthSnapshotV9 {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 32)]
        [int]$RetryCount = 8,
        [ValidateRange(0, 1000)]
        [int]$RetryDelayMilliseconds = 5
    )

    for ($attempt = 0; $attempt -lt $RetryCount; $attempt++) {
        $mapping = $null
        $view = $null
        try {
            try {
                $mapping = [IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting(
                    $script:CloudOSHealthMappingNameV9,
                    [IO.MemoryMappedFiles.MemoryMappedFileRights]::Read)
            }
            catch [IO.FileNotFoundException] {
                return $null
            }

            $view = $mapping.CreateViewAccessor(
                0,
                $script:CloudOSHealthStructureSizeV9,
                [IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)

            $first = New-Object byte[] $script:CloudOSHealthStructureSizeV9
            $second = New-Object byte[] $script:CloudOSHealthStructureSizeV9
            [void]$view.ReadArray(0, $first, 0, $first.Length)

            $sequence1 = [BitConverter]::ToUInt64($first, 32)
            if (($sequence1 -band 1) -ne 0) {
                if ($RetryDelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $RetryDelayMilliseconds }
                continue
            }

            [Threading.Thread]::MemoryBarrier()
            [void]$view.ReadArray(0, $second, 0, $second.Length)
            $sequence2 = [BitConverter]::ToUInt64($second, 32)
            if ($sequence1 -ne $sequence2 -or ($sequence2 -band 1) -ne 0) {
                if ($RetryDelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $RetryDelayMilliseconds }
                continue
            }

            $magic = [BitConverter]::ToUInt32($second, 0)
            $schema = [BitConverter]::ToUInt32($second, 4)
            $structureSize = [BitConverter]::ToUInt32($second, 8)
            if ($magic -ne $script:CloudOSHealthMagicV9 -or
                $schema -ne $script:CloudOSHealthSchemaV9 -or
                $structureSize -ne $script:CloudOSHealthStructureSizeV9) {
                # CreateFileMapping publishes the name before the producer has
                # finished zeroing/filling the first snapshot. Retry that tiny
                # initialization window; only a persistent mismatch is an ABI error.
                if ($attempt + 1 -lt $RetryCount) {
                    if ($RetryDelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $RetryDelayMilliseconds }
                    continue
                }
                throw 'CloudOS health V9 shared-memory ABI mismatch.'
            }

            return [pscustomobject][ordered]@{
                magic = $magic
                schema = $schema
                structure_size = $structureSize
                state = [BitConverter]::ToUInt32($second, 12)
                process_id = [BitConverter]::ToUInt32($second, 16)
                session_id = [BitConverter]::ToUInt32($second, 20)
                ui_thread_id = [BitConverter]::ToUInt32($second, 24)
                sequence = $sequence2
                started_tick_ms = [BitConverter]::ToUInt64($second, 40)
                ready_tick_ms = [BitConverter]::ToUInt64($second, 48)
                heartbeat_tick_ms = [BitConverter]::ToUInt64($second, 56)
                heartbeat_count = [BitConverter]::ToUInt64($second, 64)
                main_window_value = [BitConverter]::ToUInt64($second, 72)
                gdi_objects = [BitConverter]::ToUInt32($second, 80)
                user_objects = [BitConverter]::ToUInt32($second, 84)
                handle_count = [BitConverter]::ToUInt32($second, 88)
            }
        }
        finally {
            if ($view) { $view.Dispose() }
            if ($mapping) { $mapping.Dispose() }
        }
    }

    return $null
}

function Wait-CloudOSReadyV9 {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 30,
        [int]$ExpectedProcessId = 0
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $snapshot = Get-CloudOSHealthSnapshotV9
        if ($snapshot -and $snapshot.state -eq 2 -and $snapshot.ready_tick_ms -gt 0) {
            if ($ExpectedProcessId -eq 0 -or $snapshot.process_id -eq $ExpectedProcessId) {
                return $snapshot
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)

    return $null
}

function Test-CloudOSHeartbeatFreshV9 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [ValidateRange(1, 120)]
        [int]$MaximumAgeSeconds = 5
    )

    $now = [CloudOSHealthNativeV9]::GetTickCount64()
    if ([uint64]$Snapshot.heartbeat_tick_ms -gt ($now + 2000)) { return $false }
    if ([uint64]$Snapshot.heartbeat_tick_ms -gt $now) { return $true }
    $maximumAgeMilliseconds = [uint64]$MaximumAgeSeconds * [uint64]1000
    return (($now - [uint64]$Snapshot.heartbeat_tick_ms) -le $maximumAgeMilliseconds)
}
