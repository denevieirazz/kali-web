param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Busy = $false
$script:LastState = $null
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:SettingsDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CloudOS'
$script:SettingsPath = Join-Path $script:SettingsDirectory 'updater-settings.json'

function Read-UpdaterSettings {
    $settings = [ordered]@{
        repository = $script:RepoRoot
        autoCheck = $true
        autoUpdate = $true
        intervalSeconds = 30
        mode = 'safe'
        advanced = $false
        remote = ''
        branch = ''
    }

    if (-not (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf)) {
        return [pscustomobject]$settings
    }

    try {
        $saved = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.repository) { $settings.repository = [string]$saved.repository }
        if ($null -ne $saved.autoCheck) { $settings.autoCheck = [bool]$saved.autoCheck }
        if ($null -ne $saved.autoUpdate) { $settings.autoUpdate = [bool]$saved.autoUpdate }
        if ($saved.intervalSeconds) {
            $interval = [int]$saved.intervalSeconds
            if ($interval -ge 15 -and $interval -le 3600) { $settings.intervalSeconds = $interval }
        }
        if ($saved.mode -eq 'flexible') { $settings.mode = 'flexible' }
        if ($null -ne $saved.advanced) { $settings.advanced = [bool]$saved.advanced }
        if ($saved.remote) { $settings.remote = [string]$saved.remote }
        if ($saved.branch) { $settings.branch = [string]$saved.branch }
    }
    catch {
        # Invalid settings never prevent startup.
    }

    return [pscustomobject]$settings
}

function Save-UpdaterSettings {
    try {
        if (-not (Test-Path -LiteralPath $script:SettingsDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $script:SettingsDirectory -Force | Out-Null
        }

        $mode = 'safe'
        if ($modeCombo.SelectedIndex -eq 1) { $mode = 'flexible' }

        [ordered]@{
            repository = $repoTextBox.Text.Trim()
            autoCheck = $autoCheckCheckBox.Checked
            autoUpdate = $autoUpdateCheckBox.Checked
            intervalSeconds = [Math]::Max(15, [int]$intervalNumeric.Value)
            mode = $mode
            advanced = $advancedCheckBox.Checked
            remote = $remoteTextBox.Text.Trim()
            branch = $branchTextBox.Text.Trim()
        } | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    }
    catch {
        # Settings errors do not stop updates.
    }
}

function Write-UpdaterLog([string]$Message) {
    $stamp = Get-Date -Format 'HH:mm:ss'
    $logTextBox.AppendText("[$stamp] $Message`r`n")
    $logTextBox.SelectionStart = $logTextBox.TextLength
    $logTextBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
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

function Assert-Repository {
    $repository = $repoTextBox.Text.Trim()

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git was not found in PATH.'
    }
    if ([string]::IsNullOrWhiteSpace($repository) -or -not (Test-Path -LiteralPath $repository -PathType Container)) {
        throw 'Choose an existing project folder.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repository '.git'))) {
        throw 'The selected folder is not a Git repository.'
    }

    return $repository
}

function Test-RemoteBranchExists {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Remote,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    if ([string]::IsNullOrWhiteSpace($Remote) -or [string]::IsNullOrWhiteSpace($Branch)) {
        return $false
    }

    $trackingRef = "refs/remotes/$Remote/$Branch"
    $localCheck = Invoke-RepositoryGit -Repository $Repository -Arguments @('show-ref', '--verify', '--quiet', $trackingRef)
    if ($localCheck.ExitCode -eq 0) {
        return $true
    }

    $remoteCheck = Invoke-RepositoryGit -Repository $Repository -Arguments @('ls-remote', '--exit-code', '--heads', $Remote, "refs/heads/$Branch")
    return $remoteCheck.ExitCode -eq 0
}

function Get-RemoteAndBranch([string]$Repository, [string]$CurrentBranch) {
    if ($CurrentBranch -eq 'HEAD') {
        throw 'Detached HEAD detected. Checkout a branch before updating.'
    }

    $remote = ''
    $configuredBranch = ''

    $configuredRemote = Invoke-RepositoryGit -Repository $Repository -Arguments @('config', '--get', "branch.$CurrentBranch.remote")
    if ($configuredRemote.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($configuredRemote.Output) -and $configuredRemote.Output -ne '.') {
        $remote = $configuredRemote.Output.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($remote)) {
        $remoteList = Invoke-RepositoryGit -Repository $Repository -Arguments @('remote')
        if ($remoteList.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($remoteList.Output)) {
            throw 'This repository has no Git remote configured.'
        }

        $remotes = @($remoteList.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($remotes -contains 'origin') {
            $remote = 'origin'
        }
        else {
            $remote = $remotes[0]
        }
    }

    $configuredMerge = Invoke-RepositoryGit -Repository $Repository -Arguments @('config', '--get', "branch.$CurrentBranch.merge")
    if ($configuredMerge.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($configuredMerge.Output)) {
        $mergeRef = $configuredMerge.Output.Trim()
        if ($mergeRef.StartsWith('refs/heads/')) {
            $configuredBranch = $mergeRef.Substring(11)
        }
    }

    # Auto-detection rule: the local branch name wins when that branch exists on
    # the selected remote. This prevents stale upstream configuration from making
    # the updater compare integration/foo against an unrelated legacy branch.
    $branch = $CurrentBranch
    $matchingRemoteBranch = Test-RemoteBranchExists -Repository $Repository -Remote $remote -Branch $CurrentBranch
    if (-not $matchingRemoteBranch -and -not [string]::IsNullOrWhiteSpace($configuredBranch)) {
        $branch = $configuredBranch
    }
    elseif ($matchingRemoteBranch -and -not [string]::IsNullOrWhiteSpace($configuredBranch) -and $configuredBranch -ne $CurrentBranch) {
        Write-UpdaterLog "Ignoring stale upstream '$remote/$configuredBranch'; using '$remote/$CurrentBranch'."
    }

    if ($advancedCheckBox.Checked) {
        if (-not [string]::IsNullOrWhiteSpace($remoteTextBox.Text)) {
            $remote = $remoteTextBox.Text.Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($branchTextBox.Text)) {
            $branch = $branchTextBox.Text.Trim()
        }
    }

    return [pscustomobject]@{
        Remote = $remote
        Branch = $branch
        RemoteRef = "$remote/$branch"
    }
}

function Get-ProjectUpdateState {
    param([switch]$Fetch)

    $repository = Assert-Repository

    $branchResult = Invoke-RepositoryGit -Repository $repository -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($branchResult.ExitCode -ne 0) { throw "Could not read current branch: $($branchResult.Output)" }
    $currentBranch = $branchResult.Output.Trim()

    $source = Get-RemoteAndBranch -Repository $repository -CurrentBranch $currentBranch

    if ($Fetch) {
        Write-UpdaterLog "Checking $($source.Remote)/$($source.Branch)..."
        $fetchResult = Invoke-RepositoryGit -Repository $repository -Arguments @('fetch', '--prune', $source.Remote, $source.Branch)
        if ($fetchResult.ExitCode -ne 0) { throw "git fetch failed: $($fetchResult.Output)" }
    }

    $localResult = Invoke-RepositoryGit -Repository $repository -Arguments @('rev-parse', 'HEAD')
    if ($localResult.ExitCode -ne 0) { throw "Could not read local SHA: $($localResult.Output)" }

    $remoteResult = Invoke-RepositoryGit -Repository $repository -Arguments @('rev-parse', $source.RemoteRef)
    if ($remoteResult.ExitCode -ne 0) { throw "Remote ref '$($source.RemoteRef)' was not found." }

    $statusResult = Invoke-RepositoryGit -Repository $repository -Arguments @('status', '--porcelain')
    if ($statusResult.ExitCode -ne 0) { throw "Could not read working tree: $($statusResult.Output)" }

    $localSha = $localResult.Output.Trim()
    $remoteSha = $remoteResult.Output.Trim()
    $dirty = -not [string]::IsNullOrWhiteSpace($statusResult.Output)
    $relation = 'unknown'

    if ($localSha -eq $remoteSha) {
        $relation = 'equal'
    }
    else {
        $localAncestor = Invoke-RepositoryGit -Repository $repository -Arguments @('merge-base', '--is-ancestor', $localSha, $source.RemoteRef)
        if ($localAncestor.ExitCode -eq 0) {
            $relation = 'behind'
        }
        else {
            $remoteAncestor = Invoke-RepositoryGit -Repository $repository -Arguments @('merge-base', '--is-ancestor', $source.RemoteRef, $localSha)
            if ($remoteAncestor.ExitCode -eq 0) {
                $relation = 'ahead'
            }
            else {
                $relation = 'diverged'
            }
        }
    }

    $projectName = Split-Path -Leaf $repository

    return [pscustomobject]@{
        Repository = $repository
        ProjectName = $projectName
        CurrentBranch = $currentBranch
        Source = $source
        LocalSha = $localSha
        RemoteSha = $remoteSha
        Dirty = $dirty
        Relation = $relation
    }
}

function Update-AdvancedVisibility {
    $visible = $advancedCheckBox.Checked
    $remoteLabel.Visible = $visible
    $remoteTextBox.Visible = $visible
    $branchLabel.Visible = $visible
    $branchTextBox.Visible = $visible
}

function Show-ProjectUpdateState($State) {
    $script:LastState = $State

    $projectValueLabel.Text = $State.ProjectName
    $branchValueLabel.Text = $State.CurrentBranch
    $sourceValueLabel.Text = $State.Source.RemoteRef
    $localShaValueLabel.Text = $State.LocalSha.Substring(0, [Math]::Min(12, $State.LocalSha.Length))
    $remoteShaValueLabel.Text = $State.RemoteSha.Substring(0, [Math]::Min(12, $State.RemoteSha.Length))

    if ($State.Dirty) {
        $workingTreeValueLabel.Text = 'LOCAL CHANGES'
        $workingTreeValueLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
    else {
        $workingTreeValueLabel.Text = 'clean'
        $workingTreeValueLabel.ForeColor = [System.Drawing.Color]::ForestGreen
    }

    $flexible = $modeCombo.SelectedIndex -eq 1
    $canUpdate = $false

    switch ($State.Relation) {
        'equal' {
            Set-UpdaterStatus 'Project is up to date' ([System.Drawing.Color]::ForestGreen)
        }
        'behind' {
            if ($State.Dirty -and -not $flexible) {
                Set-UpdaterStatus 'Update available - use Flexible mode for local changes' ([System.Drawing.Color]::DarkOrange)
            }
            else {
                Set-UpdaterStatus 'Update available' ([System.Drawing.Color]::RoyalBlue)
                $canUpdate = $true
            }
        }
        'ahead' {
            Set-UpdaterStatus 'Local branch is ahead - nothing to download' ([System.Drawing.Color]::DarkOrange)
        }
        'diverged' {
            if ($flexible) {
                Set-UpdaterStatus 'Branches diverged - Flexible mode can rebase' ([System.Drawing.Color]::DarkOrange)
                $canUpdate = $true
            }
            else {
                Set-UpdaterStatus 'Branches diverged - switch to Flexible mode' ([System.Drawing.Color]::Firebrick)
            }
        }
        default {
            Set-UpdaterStatus 'Unknown Git state' ([System.Drawing.Color]::Firebrick)
        }
    }

    $updateButton.Enabled = $canUpdate -and -not $script:Busy
}

function Invoke-ProjectUpdateCore($State) {
    $flexible = $modeCombo.SelectedIndex -eq 1

    if ($State.Relation -eq 'equal') {
        Write-UpdaterLog 'No update is required.'
        return
    }

    if ($State.Relation -eq 'ahead') {
        Write-UpdaterLog 'Local branch is ahead. There is no remote update to download.'
        return
    }

    if (-not $flexible) {
        if ($State.Dirty) {
            throw 'Safe mode blocked the update because local changes exist.'
        }
        if ($State.Relation -ne 'behind') {
            throw "Safe mode only accepts fast-forward updates. Current state: $($State.Relation)."
        }

        Write-UpdaterLog "Fast-forwarding to $($State.RemoteSha.Substring(0, 12))..."
        $result = Invoke-RepositoryGit -Repository $State.Repository -Arguments @('merge', '--ff-only', $State.Source.RemoteRef)
        if ($result.ExitCode -ne 0) { throw "Fast-forward failed: $($result.Output)" }
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) { Write-UpdaterLog $result.Output }
        return
    }

    Write-UpdaterLog 'Flexible update: pull --rebase --autostash. Local changes will not be deleted.'
    $pullResult = Invoke-RepositoryGit -Repository $State.Repository -Arguments @('pull', '--rebase', '--autostash', $State.Source.Remote, $State.Source.Branch)
    if ($pullResult.ExitCode -ne 0) {
        throw "Flexible update stopped. Git may require conflict resolution: $($pullResult.Output)"
    }
    if (-not [string]::IsNullOrWhiteSpace($pullResult.Output)) { Write-UpdaterLog $pullResult.Output }
}

function Invoke-ProjectUpdate {
    if ($script:Busy) { return }
    $script:Busy = $true
    $checkButton.Enabled = $false
    $updateButton.Enabled = $false

    try {
        Save-UpdaterSettings
        $state = Get-ProjectUpdateState -Fetch
        Show-ProjectUpdateState $state
        Invoke-ProjectUpdateCore $state
        $newState = Get-ProjectUpdateState
        Show-ProjectUpdateState $newState
        Write-UpdaterLog "Done. Local SHA: $($newState.LocalSha.Substring(0, 12))."
    }
    catch {
        Set-UpdaterStatus 'Update stopped' ([System.Drawing.Color]::Firebrick)
        Write-UpdaterLog $_.Exception.Message
    }
    finally {
        $script:Busy = $false
        $checkButton.Enabled = $true
        if ($null -ne $script:LastState) { Show-ProjectUpdateState $script:LastState }
    }
}

function Test-ForProjectUpdate([bool]$AllowAutoUpdate) {
    if ($script:Busy) { return }
    $script:Busy = $true
    $checkButton.Enabled = $false
    $updateButton.Enabled = $false

    try {
        Save-UpdaterSettings
        $state = Get-ProjectUpdateState -Fetch
        Show-ProjectUpdateState $state
        Write-UpdaterLog "Local $($state.LocalSha.Substring(0, 12)) | Remote $($state.RemoteSha.Substring(0, 12)) | $($state.Relation)"

        $canAutoUpdate = $AllowAutoUpdate -and $autoUpdateCheckBox.Checked -and $state.Relation -eq 'behind' -and -not $state.Dirty
        if ($canAutoUpdate) {
            Write-UpdaterLog 'Automatic update is safe. Applying now...'
            Invoke-ProjectUpdateCore $state
            $state = Get-ProjectUpdateState
            Show-ProjectUpdateState $state
            Write-UpdaterLog "Automatic update completed: $($state.LocalSha.Substring(0, 12))."
        }
    }
    catch {
        Set-UpdaterStatus 'Could not check project' ([System.Drawing.Color]::Firebrick)
        Write-UpdaterLog $_.Exception.Message
    }
    finally {
        $script:Busy = $false
        $checkButton.Enabled = $true
        if ($null -ne $script:LastState) { Show-ProjectUpdateState $script:LastState }
    }
}

$settings = Read-UpdaterSettings

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Project Updater'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(860, 650)
$form.MinimumSize = New-Object System.Drawing.Size(800, 600)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Git Project Updater'
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 17)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(20, 16)
$form.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = 'Choose any Git project. Branch and remote are detected automatically.'
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object System.Drawing.Point(22, 52)
$form.Controls.Add($subtitleLabel)

$repoLabel = New-Object System.Windows.Forms.Label
$repoLabel.Text = 'Project folder'
$repoLabel.AutoSize = $true
$repoLabel.Location = New-Object System.Drawing.Point(20, 86)
$form.Controls.Add($repoLabel)

$repoTextBox = New-Object System.Windows.Forms.TextBox
$repoTextBox.Text = [string]$settings.repository
$repoTextBox.Location = New-Object System.Drawing.Point(20, 106)
$repoTextBox.Size = New-Object System.Drawing.Size(688, 24)
$repoTextBox.Anchor = 'Top,Left,Right'
$form.Controls.Add($repoTextBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = 'Browse...'
$browseButton.Location = New-Object System.Drawing.Point(718, 103)
$browseButton.Size = New-Object System.Drawing.Size(105, 29)
$browseButton.Anchor = 'Top,Right'
$form.Controls.Add($browseButton)

$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = 'Update now'
$updateButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$updateButton.Location = New-Object System.Drawing.Point(20, 148)
$updateButton.Size = New-Object System.Drawing.Size(150, 40)
$updateButton.Enabled = $false
$form.Controls.Add($updateButton)

$checkButton = New-Object System.Windows.Forms.Button
$checkButton.Text = 'Check'
$checkButton.Location = New-Object System.Drawing.Point(180, 148)
$checkButton.Size = New-Object System.Drawing.Size(100, 40)
$form.Controls.Add($checkButton)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = 'Open folder'
$openFolderButton.Location = New-Object System.Drawing.Point(290, 148)
$openFolderButton.Size = New-Object System.Drawing.Size(110, 40)
$form.Controls.Add($openFolderButton)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = 'Update mode'
$modeLabel.AutoSize = $true
$modeLabel.Location = New-Object System.Drawing.Point(425, 147)
$form.Controls.Add($modeLabel)

$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.DropDownStyle = 'DropDownList'
[void]$modeCombo.Items.Add('Safe - fast-forward only')
[void]$modeCombo.Items.Add('Flexible - rebase + autostash')
if ($settings.mode -eq 'flexible') { $modeCombo.SelectedIndex = 1 } else { $modeCombo.SelectedIndex = 0 }
$modeCombo.Location = New-Object System.Drawing.Point(425, 166)
$modeCombo.Size = New-Object System.Drawing.Size(230, 24)
$form.Controls.Add($modeCombo)

$advancedCheckBox = New-Object System.Windows.Forms.CheckBox
$advancedCheckBox.Text = 'Advanced overrides'
$advancedCheckBox.Checked = [bool]$settings.advanced
$advancedCheckBox.AutoSize = $true
$advancedCheckBox.Location = New-Object System.Drawing.Point(675, 168)
$form.Controls.Add($advancedCheckBox)

$remoteLabel = New-Object System.Windows.Forms.Label
$remoteLabel.Text = 'Remote override'
$remoteLabel.AutoSize = $true
$remoteLabel.Location = New-Object System.Drawing.Point(20, 202)
$form.Controls.Add($remoteLabel)

$remoteTextBox = New-Object System.Windows.Forms.TextBox
$remoteTextBox.Text = [string]$settings.remote
$remoteTextBox.Location = New-Object System.Drawing.Point(20, 222)
$remoteTextBox.Size = New-Object System.Drawing.Size(180, 24)
$form.Controls.Add($remoteTextBox)

$branchLabel = New-Object System.Windows.Forms.Label
$branchLabel.Text = 'Branch override'
$branchLabel.AutoSize = $true
$branchLabel.Location = New-Object System.Drawing.Point(220, 202)
$form.Controls.Add($branchLabel)

$branchTextBox = New-Object System.Windows.Forms.TextBox
$branchTextBox.Text = [string]$settings.branch
$branchTextBox.Location = New-Object System.Drawing.Point(220, 222)
$branchTextBox.Size = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($branchTextBox)

$autoCheckCheckBox = New-Object System.Windows.Forms.CheckBox
$autoCheckCheckBox.Text = 'Check automatically'
$autoCheckCheckBox.Checked = [bool]$settings.autoCheck
$autoCheckCheckBox.AutoSize = $true
$autoCheckCheckBox.Location = New-Object System.Drawing.Point(20, 264)
$form.Controls.Add($autoCheckCheckBox)

$autoUpdateCheckBox = New-Object System.Windows.Forms.CheckBox
$autoUpdateCheckBox.Text = 'Auto-update when clean and safe'
$autoUpdateCheckBox.Checked = [bool]$settings.autoUpdate
$autoUpdateCheckBox.AutoSize = $true
$autoUpdateCheckBox.Location = New-Object System.Drawing.Point(175, 264)
$form.Controls.Add($autoUpdateCheckBox)

$everyLabel = New-Object System.Windows.Forms.Label
$everyLabel.Text = 'every'
$everyLabel.AutoSize = $true
$everyLabel.Location = New-Object System.Drawing.Point(400, 266)
$form.Controls.Add($everyLabel)

$intervalNumeric = New-Object System.Windows.Forms.NumericUpDown
$intervalNumeric.Minimum = 15
$intervalNumeric.Maximum = 3600
$intervalNumeric.Value = [Math]::Min(3600, [Math]::Max(15, [int]$settings.intervalSeconds))
$intervalNumeric.Location = New-Object System.Drawing.Point(440, 262)
$intervalNumeric.Size = New-Object System.Drawing.Size(70, 24)
$form.Controls.Add($intervalNumeric)

$secondsLabel = New-Object System.Windows.Forms.Label
$secondsLabel.Text = 'seconds'
$secondsLabel.AutoSize = $true
$secondsLabel.Location = New-Object System.Drawing.Point(518, 266)
$form.Controls.Add($secondsLabel)

$statusCaptionLabel = New-Object System.Windows.Forms.Label
$statusCaptionLabel.Text = 'Status:'
$statusCaptionLabel.AutoSize = $true
$statusCaptionLabel.Location = New-Object System.Drawing.Point(20, 302)
$form.Controls.Add($statusCaptionLabel)

$statusValueLabel = New-Object System.Windows.Forms.Label
$statusValueLabel.Text = 'Waiting for check'
$statusValueLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$statusValueLabel.AutoSize = $true
$statusValueLabel.Location = New-Object System.Drawing.Point(75, 300)
$form.Controls.Add($statusValueLabel)

$projectCaptionLabel = New-Object System.Windows.Forms.Label
$projectCaptionLabel.Text = 'Project:'
$projectCaptionLabel.AutoSize = $true
$projectCaptionLabel.Location = New-Object System.Drawing.Point(20, 332)
$form.Controls.Add($projectCaptionLabel)
$projectValueLabel = New-Object System.Windows.Forms.Label
$projectValueLabel.Text = '-'
$projectValueLabel.AutoSize = $true
$projectValueLabel.Location = New-Object System.Drawing.Point(75, 332)
$form.Controls.Add($projectValueLabel)

$branchCaptionLabel = New-Object System.Windows.Forms.Label
$branchCaptionLabel.Text = 'Branch:'
$branchCaptionLabel.AutoSize = $true
$branchCaptionLabel.Location = New-Object System.Drawing.Point(220, 332)
$form.Controls.Add($branchCaptionLabel)
$branchValueLabel = New-Object System.Windows.Forms.Label
$branchValueLabel.Text = '-'
$branchValueLabel.AutoSize = $true
$branchValueLabel.Location = New-Object System.Drawing.Point(275, 332)
$form.Controls.Add($branchValueLabel)

$sourceCaptionLabel = New-Object System.Windows.Forms.Label
$sourceCaptionLabel.Text = 'Source:'
$sourceCaptionLabel.AutoSize = $true
$sourceCaptionLabel.Location = New-Object System.Drawing.Point(470, 332)
$form.Controls.Add($sourceCaptionLabel)
$sourceValueLabel = New-Object System.Windows.Forms.Label
$sourceValueLabel.Text = '-'
$sourceValueLabel.AutoSize = $true
$sourceValueLabel.Location = New-Object System.Drawing.Point(525, 332)
$form.Controls.Add($sourceValueLabel)

$localShaCaptionLabel = New-Object System.Windows.Forms.Label
$localShaCaptionLabel.Text = 'Local SHA:'
$localShaCaptionLabel.AutoSize = $true
$localShaCaptionLabel.Location = New-Object System.Drawing.Point(20, 358)
$form.Controls.Add($localShaCaptionLabel)
$localShaValueLabel = New-Object System.Windows.Forms.Label
$localShaValueLabel.Text = '-'
$localShaValueLabel.AutoSize = $true
$localShaValueLabel.Location = New-Object System.Drawing.Point(90, 358)
$form.Controls.Add($localShaValueLabel)

$remoteShaCaptionLabel = New-Object System.Windows.Forms.Label
$remoteShaCaptionLabel.Text = 'Remote SHA:'
$remoteShaCaptionLabel.AutoSize = $true
$remoteShaCaptionLabel.Location = New-Object System.Drawing.Point(220, 358)
$form.Controls.Add($remoteShaCaptionLabel)
$remoteShaValueLabel = New-Object System.Windows.Forms.Label
$remoteShaValueLabel.Text = '-'
$remoteShaValueLabel.AutoSize = $true
$remoteShaValueLabel.Location = New-Object System.Drawing.Point(305, 358)
$form.Controls.Add($remoteShaValueLabel)

$workingTreeCaptionLabel = New-Object System.Windows.Forms.Label
$workingTreeCaptionLabel.Text = 'Working tree:'
$workingTreeCaptionLabel.AutoSize = $true
$workingTreeCaptionLabel.Location = New-Object System.Drawing.Point(470, 358)
$form.Controls.Add($workingTreeCaptionLabel)
$workingTreeValueLabel = New-Object System.Windows.Forms.Label
$workingTreeValueLabel.Text = '-'
$workingTreeValueLabel.AutoSize = $true
$workingTreeValueLabel.Location = New-Object System.Drawing.Point(560, 358)
$form.Controls.Add($workingTreeValueLabel)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = 'Log'
$logLabel.AutoSize = $true
$logLabel.Location = New-Object System.Drawing.Point(20, 394)
$form.Controls.Add($logLabel)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Multiline = $true
$logTextBox.ReadOnly = $true
$logTextBox.ScrollBars = 'Vertical'
$logTextBox.Location = New-Object System.Drawing.Point(20, 414)
$logTextBox.Size = New-Object System.Drawing.Size(803, 180)
$logTextBox.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($logTextBox)

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$browseButton.Add_Click({
    $folderDialog.SelectedPath = $repoTextBox.Text
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $repoTextBox.Text = $folderDialog.SelectedPath
        Save-UpdaterSettings
        Test-ForProjectUpdate $false
    }
})

$checkButton.Add_Click({ Test-ForProjectUpdate $false })
$updateButton.Add_Click({ Invoke-ProjectUpdate })
$openFolderButton.Add_Click({
    $path = $repoTextBox.Text.Trim()
    if (Test-Path -LiteralPath $path -PathType Container) {
        Start-Process explorer.exe -ArgumentList @($path)
    }
})

$advancedCheckBox.Add_CheckedChanged({
    Update-AdvancedVisibility
    Save-UpdaterSettings
})
$modeCombo.Add_SelectedIndexChanged({
    Save-UpdaterSettings
    if ($null -ne $script:LastState) { Show-ProjectUpdateState $script:LastState }
})
$repoTextBox.Add_Leave({ Save-UpdaterSettings })
$remoteTextBox.Add_Leave({ Save-UpdaterSettings })
$branchTextBox.Add_Leave({ Save-UpdaterSettings })
$autoCheckCheckBox.Add_CheckedChanged({ Save-UpdaterSettings })
$autoUpdateCheckBox.Add_CheckedChanged({ Save-UpdaterSettings })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [int]$intervalNumeric.Value * 1000
$timer.Add_Tick({
    if ($autoCheckCheckBox.Checked -and -not $script:Busy) {
        Test-ForProjectUpdate $true
    }
})
$intervalNumeric.Add_ValueChanged({
    $timer.Interval = [int]$intervalNumeric.Value * 1000
    Save-UpdaterSettings
})

$form.Add_Shown({
    Update-AdvancedVisibility
    Write-UpdaterLog 'Project Updater started. No reset --hard or force operations are used.'
    if ($autoCheckCheckBox.Checked) { Test-ForProjectUpdate $true }
    $timer.Start()
})
$form.Add_FormClosing({
    $timer.Stop()
    Save-UpdaterSettings
})

[void]$form.ShowDialog()
