param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:DefaultBranch = 'integration/cloudos-unified-runtime'
$script:DefaultRemote = 'origin'
$script:Busy = $false
$script:LastState = $null
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:SettingsDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudOS'
$script:SettingsPath = Join-Path $script:SettingsDirectory 'updater-settings.json'

function Read-UpdaterSettings {
    $settings = [ordered]@{
        repository = $script:RepoRoot
        remote = $script:DefaultRemote
        branch = $script:DefaultBranch
        autoCheck = $true
        autoUpdate = $true
        intervalSeconds = 30
    }

    if (-not (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf)) {
        return [pscustomobject]$settings
    }

    try {
        $saved = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.repository) { $settings.repository = [string]$saved.repository }
        if ($saved.remote) { $settings.remote = [string]$saved.remote }
        if ($saved.branch) { $settings.branch = [string]$saved.branch }
        if ($null -ne $saved.autoCheck) { $settings.autoCheck = [bool]$saved.autoCheck }
        if ($null -ne $saved.autoUpdate) { $settings.autoUpdate = [bool]$saved.autoUpdate }
        if ($saved.intervalSeconds) {
            $interval = [int]$saved.intervalSeconds
            if ($interval -ge 15 -and $interval -le 3600) {
                $settings.intervalSeconds = $interval
            }
        }
    }
    catch {
        # Invalid settings must never prevent the updater from starting.
    }

    return [pscustomobject]$settings
}

function Write-UpdaterLog([string]$Message) {
    if ($null -eq $logTextBox) { return }
    $stamp = Get-Date -Format 'HH:mm:ss'
    $logTextBox.AppendText("[$stamp] $Message`r`n")
    $logTextBox.SelectionStart = $logTextBox.TextLength
    $logTextBox.ScrollToCaret()
}

function Save-UpdaterSettings {
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $script:SettingsDirectory -Force | Out-Null
        }

        [ordered]@{
            repository = $repoTextBox.Text.Trim()
            remote = $remoteTextBox.Text.Trim()
            branch = $branchTextBox.Text.Trim()
            autoCheck = $autoCheckCheckBox.Checked
            autoUpdate = $autoUpdateCheckBox.Checked
            intervalSeconds = [Math]::Max(15, [int]$intervalNumeric.Value)
        } | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    }
    catch {
        Write-UpdaterLog "Warning: could not save updater settings: $($_.Exception.Message)"
    }
}

function Set-UpdaterStatus([string]$Text, [System.Drawing.Color]$Color) {
    $statusValueLabel.Text = $Text
    $statusValueLabel.ForeColor = $Color
}

function Invoke-RepositoryGit {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $Repository
    try {
        $lines = @(& git @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
        $ErrorActionPreference = $previousErrorAction
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}

function Get-UpdaterConfiguration {
    $repository = $repoTextBox.Text.Trim()
    $remote = $remoteTextBox.Text.Trim()
    $branch = $branchTextBox.Text.Trim()

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'Git was not found in PATH. Install Git for Windows and reopen the updater.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($repository) -or -not (Test-Path -LiteralPath $repository -PathType Container)) {
        throw 'Repository folder does not exist.'
    }

    $insideResult = Invoke-RepositoryGit -Repository $repository -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($insideResult.ExitCode -ne 0 -or $insideResult.Output.Trim() -ne 'true') {
        throw 'Selected folder is not a Git working tree.'
    }

    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw 'Enter the Git remote name, normally origin.'
    }

    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Enter the branch that must receive updates.'
    }

    return [pscustomobject]@{
        Repository = $repository
        Remote = $remote
        Branch = $branch
        RemoteRef = "$remote/$branch"
    }
}

function Get-CloudOSUpdateState {
    param([switch]$Fetch)

    $config = Get-UpdaterConfiguration

    $branchResult = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($branchResult.ExitCode -ne 0) {
        throw "Could not read current branch: $($branchResult.Output)"
    }

    $localResult = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('rev-parse', 'HEAD')
    if ($localResult.ExitCode -ne 0) {
        throw "Could not read local SHA: $($localResult.Output)"
    }

    $statusResult = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('status', '--porcelain')
    if ($statusResult.ExitCode -ne 0) {
        throw "Could not read working tree state: $($statusResult.Output)"
    }

    if ($Fetch) {
        Write-UpdaterLog "Checking $($config.Remote)/$($config.Branch)..."
        $fetchResult = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('fetch', '--prune', $config.Remote)
        if ($fetchResult.ExitCode -ne 0) {
            throw "git fetch failed: $($fetchResult.Output)"
        }
    }

    $remoteResult = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('rev-parse', $config.RemoteRef)
    if ($remoteResult.ExitCode -ne 0) {
        throw "Remote ref $($config.RemoteRef) was not found after fetch."
    }

    $localSha = $localResult.Output.Trim()
    $remoteSha = $remoteResult.Output.Trim()
    $dirty = -not [string]::IsNullOrWhiteSpace($statusResult.Output)
    $relation = 'unknown'

    if ($localSha -eq $remoteSha) {
        $relation = 'equal'
    }
    else {
        $localAncestor = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('merge-base', '--is-ancestor', $localSha, $config.RemoteRef)
        if ($localAncestor.ExitCode -eq 0) {
            $relation = 'behind'
        }
        else {
            $remoteAncestor = Invoke-RepositoryGit -Repository $config.Repository -Arguments @('merge-base', '--is-ancestor', $config.RemoteRef, $localSha)
            if ($remoteAncestor.ExitCode -eq 0) {
                $relation = 'ahead'
            }
            else {
                $relation = 'diverged'
            }
        }
    }

    return [pscustomobject]@{
        Config = $config
        CurrentBranch = $branchResult.Output.Trim()
        LocalSha = $localSha
        RemoteSha = $remoteSha
        Dirty = $dirty
        Relation = $relation
    }
}

function Show-CloudOSUpdateState($State) {
    $script:LastState = $State

    $currentShaValueLabel.Text = $State.LocalSha.Substring(0, [Math]::Min(12, $State.LocalSha.Length))
    $remoteShaValueLabel.Text = $State.RemoteSha.Substring(0, [Math]::Min(12, $State.RemoteSha.Length))

    if ($State.Dirty) {
        $workingTreeValueLabel.Text = 'LOCAL CHANGES'
        $workingTreeValueLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    else {
        $workingTreeValueLabel.Text = 'clean'
        $workingTreeValueLabel.ForeColor = [System.Drawing.Color]::ForestGreen
    }

    if ($State.CurrentBranch -ne $State.Config.Branch) {
        Set-UpdaterStatus "Current branch: $($State.CurrentBranch) | expected: $($State.Config.Branch)" ([System.Drawing.Color]::DarkOrange)
        $updateButton.Enabled = $false
        return
    }

    switch ($State.Relation) {
        'equal' {
            Set-UpdaterStatus 'CloudOS is up to date' ([System.Drawing.Color]::ForestGreen)
            $updateButton.Enabled = $false
        }
        'behind' {
            if ($State.Dirty) {
                Set-UpdaterStatus 'Update available, but local changes block it' ([System.Drawing.Color]::DarkOrange)
                $updateButton.Enabled = $false
            }
            else {
                Set-UpdaterStatus 'Update available' ([System.Drawing.Color]::RoyalBlue)
                $updateButton.Enabled = $true
            }
        }
        'ahead' {
            Set-UpdaterStatus 'Local branch is ahead of GitHub' ([System.Drawing.Color]::DarkOrange)
            $updateButton.Enabled = $false
        }
        'diverged' {
            Set-UpdaterStatus 'Local branch and GitHub diverged. Automatic update blocked.' ([System.Drawing.Color]::Firebrick)
            $updateButton.Enabled = $false
        }
        default {
            Set-UpdaterStatus 'Unknown Git state' ([System.Drawing.Color]::Firebrick)
            $updateButton.Enabled = $false
        }
    }
}

function Invoke-CloudOSUpdate {
    param($KnownState = $null)

    $ownsBusyFlag = -not $script:Busy
    if ($ownsBusyFlag) {
        $script:Busy = $true
    }

    $updateButton.Enabled = $false
    $checkButton.Enabled = $false

    try {
        Save-UpdaterSettings

        $state = $KnownState
        if ($null -eq $state) {
            $state = Get-CloudOSUpdateState -Fetch
        }

        if ($state.CurrentBranch -ne $state.Config.Branch) {
            throw "Update blocked: current branch is '$($state.CurrentBranch)', expected '$($state.Config.Branch)'."
        }

        if ($state.Dirty) {
            throw 'Update blocked: modified or untracked files exist. The updater will never delete them.'
        }

        if ($state.Relation -eq 'equal') {
            Show-CloudOSUpdateState $state
            Write-UpdaterLog 'No update is required.'
            return
        }

        if ($state.Relation -ne 'behind') {
            throw "Automatic update refused because Git relation is '$($state.Relation)'. Only fast-forward is allowed."
        }

        $oldSha = $state.LocalSha
        Write-UpdaterLog "Applying fast-forward to $($state.RemoteSha.Substring(0, 12))..."

        $mergeResult = Invoke-RepositoryGit -Repository $state.Config.Repository -Arguments @('merge', '--ff-only', $state.Config.RemoteRef)
        if ($mergeResult.ExitCode -ne 0) {
            throw "Fast-forward failed: $($mergeResult.Output)"
        }

        if (-not [string]::IsNullOrWhiteSpace($mergeResult.Output)) {
            Write-UpdaterLog $mergeResult.Output
        }

        $newState = Get-CloudOSUpdateState
        Show-CloudOSUpdateState $newState
        Write-UpdaterLog "Updated: $($oldSha.Substring(0, 12)) -> $($newState.LocalSha.Substring(0, 12))."
    }
    catch {
        Set-UpdaterStatus 'Update was not applied' ([System.Drawing.Color]::Firebrick)
        Write-UpdaterLog $_.Exception.Message
    }
    finally {
        $checkButton.Enabled = $true
        if ($ownsBusyFlag) {
            $script:Busy = $false
        }
    }
}

function Test-ForCloudOSUpdate([bool]$AllowAutoUpdate) {
    if ($script:Busy) {
        return
    }

    $script:Busy = $true
    $checkButton.Enabled = $false

    try {
        Save-UpdaterSettings
        $state = Get-CloudOSUpdateState -Fetch
        Show-CloudOSUpdateState $state
        Write-UpdaterLog "Local $($state.LocalSha.Substring(0, 12)) | GitHub $($state.RemoteSha.Substring(0, 12)) | $($state.Relation)"

        $canAutoUpdate = ($AllowAutoUpdate -and $autoUpdateCheckBox.Checked -and $state.Relation -eq 'behind' -and -not $state.Dirty -and $state.CurrentBranch -eq $state.Config.Branch)
        if ($canAutoUpdate) {
            Invoke-CloudOSUpdate -KnownState $state
        }
    }
    catch {
        Set-UpdaterStatus 'Could not check for updates' ([System.Drawing.Color]::Firebrick)
        Write-UpdaterLog $_.Exception.Message
    }
    finally {
        $checkButton.Enabled = $true
        $script:Busy = $false
    }
}

$settings = Read-UpdaterSettings

$form = New-Object System.Windows.Forms.Form
$form.Text = 'CloudOS Updater'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(840, 640)
$form.MinimumSize = New-Object System.Drawing.Size(780, 580)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'CloudOS - GitHub Updater'
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = 'Safe updater: fetch + fast-forward only. Local changes are never deleted.'
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($subtitleLabel)

function Add-FieldLabel([string]$Text, [int]$Left, [int]$Top) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point($Left, $Top)
    $form.Controls.Add($label)
}

Add-FieldLabel 'Repository folder' 20 86
$repoTextBox = New-Object System.Windows.Forms.TextBox
$repoTextBox.Text = [string]$settings.repository
$repoTextBox.Location = New-Object System.Drawing.Point(20, 106)
$repoTextBox.Size = New-Object System.Drawing.Size(680, 24)
$repoTextBox.Anchor = 'Top,Left,Right'
$form.Controls.Add($repoTextBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
$browseButton.Location = New-Object System.Drawing.Point(710, 104)
$browseButton.Size = New-Object System.Drawing.Size(92, 28)
$browseButton.Anchor = 'Top,Right'
$form.Controls.Add($browseButton)

Add-FieldLabel 'Remote' 20 142
$remoteTextBox = New-Object System.Windows.Forms.TextBox
$remoteTextBox.Text = [string]$settings.remote
$remoteTextBox.Location = New-Object System.Drawing.Point(20, 162)
$remoteTextBox.Size = New-Object System.Drawing.Size(150, 24)
$form.Controls.Add($remoteTextBox)

Add-FieldLabel 'Update branch' 190 142
$branchTextBox = New-Object System.Windows.Forms.TextBox
$branchTextBox.Text = [string]$settings.branch
$branchTextBox.Location = New-Object System.Drawing.Point(190, 162)
$branchTextBox.Size = New-Object System.Drawing.Size(390, 24)
$form.Controls.Add($branchTextBox)

$autoCheckCheckBox = New-Object System.Windows.Forms.CheckBox
$autoCheckCheckBox.Text = 'Check automatically'
$autoCheckCheckBox.Checked = [bool]$settings.autoCheck
$autoCheckCheckBox.AutoSize = $true
$autoCheckCheckBox.Location = New-Object System.Drawing.Point(20, 204)
$form.Controls.Add($autoCheckCheckBox)

$autoUpdateCheckBox = New-Object System.Windows.Forms.CheckBox
$autoUpdateCheckBox.Text = 'Update automatically when safe'
$autoUpdateCheckBox.Checked = [bool]$settings.autoUpdate
$autoUpdateCheckBox.AutoSize = $true
$autoUpdateCheckBox.Location = New-Object System.Drawing.Point(190, 204)
$form.Controls.Add($autoUpdateCheckBox)

$intervalLabel = New-Object System.Windows.Forms.Label
$intervalLabel.Text = 'every'
$intervalLabel.AutoSize = $true
$intervalLabel.Location = New-Object System.Drawing.Point(460, 206)
$form.Controls.Add($intervalLabel)

$intervalNumeric = New-Object System.Windows.Forms.NumericUpDown
$intervalNumeric.Minimum = 15
$intervalNumeric.Maximum = 3600
$intervalNumeric.Value = [Math]::Min(3600, [Math]::Max(15, [int]$settings.intervalSeconds))
$intervalNumeric.Location = New-Object System.Drawing.Point(505, 202)
$intervalNumeric.Size = New-Object System.Drawing.Size(70, 24)
$form.Controls.Add($intervalNumeric)

$secondsLabel = New-Object System.Windows.Forms.Label
$secondsLabel.Text = 'seconds'
$secondsLabel.AutoSize = $true
$secondsLabel.Location = New-Object System.Drawing.Point(582, 206)
$form.Controls.Add($secondsLabel)

$statusCaptionLabel = New-Object System.Windows.Forms.Label
$statusCaptionLabel.Text = 'Status:'
$statusCaptionLabel.AutoSize = $true
$statusCaptionLabel.Location = New-Object System.Drawing.Point(20, 246)
$form.Controls.Add($statusCaptionLabel)

$statusValueLabel = New-Object System.Windows.Forms.Label
$statusValueLabel.Text = 'Waiting for first check'
$statusValueLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$statusValueLabel.AutoSize = $true
$statusValueLabel.Location = New-Object System.Drawing.Point(75, 244)
$form.Controls.Add($statusValueLabel)

$currentShaCaptionLabel = New-Object System.Windows.Forms.Label
$currentShaCaptionLabel.Text = 'Local SHA:'
$currentShaCaptionLabel.AutoSize = $true
$currentShaCaptionLabel.Location = New-Object System.Drawing.Point(20, 276)
$form.Controls.Add($currentShaCaptionLabel)

$currentShaValueLabel = New-Object System.Windows.Forms.Label
$currentShaValueLabel.Text = '-'
$currentShaValueLabel.AutoSize = $true
$currentShaValueLabel.Location = New-Object System.Drawing.Point(88, 276)
$form.Controls.Add($currentShaValueLabel)

$remoteShaCaptionLabel = New-Object System.Windows.Forms.Label
$remoteShaCaptionLabel.Text = 'GitHub SHA:'
$remoteShaCaptionLabel.AutoSize = $true
$remoteShaCaptionLabel.Location = New-Object System.Drawing.Point(230, 276)
$form.Controls.Add($remoteShaCaptionLabel)

$remoteShaValueLabel = New-Object System.Windows.Forms.Label
$remoteShaValueLabel.Text = '-'
$remoteShaValueLabel.AutoSize = $true
$remoteShaValueLabel.Location = New-Object System.Drawing.Point(308, 276)
$form.Controls.Add($remoteShaValueLabel)

$workingTreeCaptionLabel = New-Object System.Windows.Forms.Label
$workingTreeCaptionLabel.Text = 'Working tree:'
$workingTreeCaptionLabel.AutoSize = $true
$workingTreeCaptionLabel.Location = New-Object System.Drawing.Point(450, 276)
$form.Controls.Add($workingTreeCaptionLabel)

$workingTreeValueLabel = New-Object System.Windows.Forms.Label
$workingTreeValueLabel.Text = '-'
$workingTreeValueLabel.AutoSize = $true
$workingTreeValueLabel.Location = New-Object System.Drawing.Point(540, 276)
$form.Controls.Add($workingTreeValueLabel)

$checkButton = New-Object System.Windows.Forms.Button
$checkButton.Text = 'Check now'
$checkButton.Location = New-Object System.Drawing.Point(20, 310)
$checkButton.Size = New-Object System.Drawing.Size(130, 34)
$form.Controls.Add($checkButton)

$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = 'Update now'
$updateButton.Location = New-Object System.Drawing.Point(160, 310)
$updateButton.Size = New-Object System.Drawing.Size(120, 34)
$updateButton.Enabled = $false
$form.Controls.Add($updateButton)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = 'Open folder'
$openFolderButton.Location = New-Object System.Drawing.Point(290, 310)
$openFolderButton.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($openFolderButton)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = 'Log'
$logLabel.AutoSize = $true
$logLabel.Location = New-Object System.Drawing.Point(20, 360)
$form.Controls.Add($logLabel)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Multiline = $true
$logTextBox.ReadOnly = $true
$logTextBox.ScrollBars = 'Vertical'
$logTextBox.Location = New-Object System.Drawing.Point(20, 382)
$logTextBox.Size = New-Object System.Drawing.Size(782, 200)
$logTextBox.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($logTextBox)

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog

$browseButton.Add_Click({
    if (Test-Path -LiteralPath $repoTextBox.Text -PathType Container) {
        $folderDialog.SelectedPath = $repoTextBox.Text
    }

    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $repoTextBox.Text = $folderDialog.SelectedPath
        Save-UpdaterSettings
    }
})

$checkButton.Add_Click({
    Test-ForCloudOSUpdate $false
})

$updateButton.Add_Click({
    if (-not $script:Busy) {
        Invoke-CloudOSUpdate
    }
})

$openFolderButton.Add_Click({
    $path = $repoTextBox.Text.Trim()
    if (Test-Path -LiteralPath $path -PathType Container) {
        Start-Process explorer.exe -ArgumentList @($path)
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [int]$intervalNumeric.Value * 1000
$timer.Add_Tick({
    if ($autoCheckCheckBox.Checked -and -not $script:Busy) {
        Test-ForCloudOSUpdate $true
    }
})

$intervalNumeric.Add_ValueChanged({
    $timer.Interval = [int]$intervalNumeric.Value * 1000
    Save-UpdaterSettings
})

$autoCheckCheckBox.Add_CheckedChanged({ Save-UpdaterSettings })
$autoUpdateCheckBox.Add_CheckedChanged({ Save-UpdaterSettings })
$repoTextBox.Add_Leave({ Save-UpdaterSettings })
$remoteTextBox.Add_Leave({ Save-UpdaterSettings })
$branchTextBox.Add_Leave({ Save-UpdaterSettings })

$form.Add_Shown({
    Write-UpdaterLog 'Updater started. reset --hard and force operations are not used.'
    if ($autoCheckCheckBox.Checked) {
        Test-ForCloudOSUpdate $true
    }
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
    Save-UpdaterSettings
})

[void]$form.ShowDialog()
