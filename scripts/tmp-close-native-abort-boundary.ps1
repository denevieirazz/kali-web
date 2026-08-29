$ErrorActionPreference = 'Stop'
$path = 'desktop/CloudOS.Host/Bridge/WebMessageBridge.cs'
$text = Get-Content -LiteralPath $path -Raw
$old = @'
            if (!NativeLaunchContainmentPolicy.CanReportManaged(processTracked, hasTrackableWindow, sharedBroker))
            {
                TerminateProcessAndForget(launchLease.ProcessId, NativeContainmentFailure.QuarantineFailed);
                throw new BridgeException("WINDOW_CONTAINMENT_DENIED", "A janela não pôde ser marcada como gerenciada.");
            }
'@
$new = @'
            if (!NativeLaunchContainmentPolicy.CanReportManaged(processTracked, hasTrackableWindow, sharedBroker))
            {
                throw new BridgeException(
                    "WINDOW_CONTAINMENT_DENIED",
                    "A janela não pôde ser marcada como gerenciada.",
                    NativeContainmentFailure.QuarantineFailed);
            }
'@
$matches = ([regex]::Matches($text, [regex]::Escape($old))).Count
if ($matches -ne 1) { throw "MANAGED_BOUNDARY_PATTERN_COUNT=$matches" }
$text = $text.Replace($old, $new)
Set-Content -LiteralPath $path -Value $text -Encoding utf8 -NoNewline
