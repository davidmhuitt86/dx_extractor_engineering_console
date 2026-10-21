# DX-Extractor Engineering Console
# Local validation only. This script does not change branches, reset files, commit, push, or publish.
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('', 'ALL', 'BUILD', 'TEST', 'ARTIFACTS', 'GUARD', 'DIAGNOSTIC')]
    [string]$RunMode = ''
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = $RepositoryRoot.TrimEnd([char[]]@('\', '/'))
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [System.IO.Path]::GetPathRoot((Get-Location).Path)
}
$root = [System.IO.Path]::GetFullPath($RepositoryRoot)
if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
    throw "Not a Git repository: $root"
}
$logDir = Join-Path $root 'artifacts\engineering-console'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Executable,
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )
    [System.Console]::Out.WriteLine('')
    [System.Console]::Out.WriteLine(("===== {0} =====" -f $Name))
    [System.Console]::Out.WriteLine(("COMMAND: {0} {1}" -f $Executable, ($Arguments -join ' ')))
    & $Executable @Arguments 2>&1 | ForEach-Object { [System.Console]::Out.WriteLine([string]$_) }
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    if ($exitCode -eq 0) {
        [System.Console]::Out.WriteLine('RESULT: PASS')
        return $true
    }
    [System.Console]::Out.WriteLine(("RESULT: FAIL (exit {0})" -f $exitCode))
    return $false
}

if ($RunMode) {
    $failed = $false
    $buildDir = Join-Path $root 'build'
    $cmake = (Get-Command 'cmake.exe' -ErrorAction Stop).Source
    $ctest = (Get-Command 'ctest.exe' -ErrorAction Stop).Source

    if ($RunMode -in @('ALL','BUILD','TEST')) {
        if (-not (Test-Path -LiteralPath (Join-Path $buildDir 'CMakeCache.txt'))) {
            if (-not (Invoke-LoggedCommand 'Configure CMake' $cmake @('-S', $root, '-B', $buildDir))) {
                $failed = $true
            }
        }
    }
    if (-not $failed -and $RunMode -in @('ALL','BUILD')) {
        if (-not (Invoke-LoggedCommand 'Release build' $cmake @('--build', $buildDir, '--config', 'Release', '--parallel', '1'))) {
            $failed = $true
        }
    }
    if (-not $failed -and $RunMode -in @('ALL','TEST')) {
        if (-not (Invoke-LoggedCommand 'CTest Release suite' $ctest @('--test-dir', $buildDir, '-C', 'Release', '--output-on-failure'))) {
            $failed = $true
        }
    }
    if ($RunMode -in @('ALL','ARTIFACTS')) {
        Write-Output ''
        Write-Output '===== Review artifact JSON validation ====='
        $artifactPaths = @(
            (Join-Path $root 'artifacts\extraction_review\review_manifest.json'),
            (Join-Path $root 'artifacts\audit\extraction_audit.json')
        )
        foreach ($artifactPath in $artifactPaths) {
            if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
                Write-Output ("FAIL: missing artifact: {0}" -f $artifactPath)
                $failed = $true
                continue
            }
            try {
                $jsonText = [System.IO.File]::ReadAllText($artifactPath, [System.Text.Encoding]::UTF8)
                $data = ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop
                if ($null -eq $data -or $data -is [System.Array] -or $data -is [string]) {
                    throw 'Expected a top-level JSON object.'
                }
                Write-Output ("VALID JSON: {0}" -f $artifactPath)
                if ([System.IO.Path]::GetFileName($artifactPath) -eq 'review_manifest.json') {
                    foreach ($field in @('source_id','page','image_width','image_height','layers')) {
                        if ($null -eq $data.PSObject.Properties[$field]) {
                            Write-Output ("FAIL: manifest missing required field: {0}" -f $field)
                            $failed = $true
                        }
                    }
                }
            }
            catch {
                Write-Output ("FAIL: invalid artifact JSON: {0}" -f $artifactPath)
                Write-Output $_.Exception.Message
                $failed = $true
            }
        }
    }
    if ($RunMode -in @('ALL','GUARD')) {
        $guard = Join-Path $root 'tools\tests\test-dx-publish-review-integrity.ps1'
        $windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $guard -PathType Leaf) {
            if (-not (Invoke-LoggedCommand 'Publication guard regression tests' $windowsPowerShell @('-NoProfile','-ExecutionPolicy','Bypass','-File',$guard))) {
                $failed = $true
            }
        }
        else {
            Write-Output ("FAIL: missing guard test script: {0}" -f $guard)
            $failed = $true
        }
    }
    if ($failed) {
        Write-Output ''
        Write-Output 'OVERALL: FAIL'
        exit 1
    }
    Write-Output ''
    Write-Output 'OVERALL: PASS'
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'DX-Extractor Engineering Console'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1000, 680)
$form.MinimumSize = New-Object System.Drawing.Size(800, 520)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 78
$header.BackColor = [System.Drawing.Color]::FromArgb(32, 47, 65)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'DX-EXTRACTOR ENGINEERING CONSOLE'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 10)
$title.AutoSize = $true
$header.Controls.Add($title)

$repoLabel = New-Object System.Windows.Forms.Label
$repoLabel.Text = "Repository: $root"
$repoLabel.ForeColor = [System.Drawing.Color]::White
$repoLabel.Location = New-Object System.Drawing.Point(18, 47)
$repoLabel.AutoSize = $true
$header.Controls.Add($repoLabel)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Dock = 'Top'
$buttons.Height = 50
$buttons.Padding = New-Object System.Windows.Forms.Padding(8)
$form.Controls.Add($buttons)

$diagnosticPanel = New-Object System.Windows.Forms.Panel
$diagnosticPanel.Dock = 'Top'
$diagnosticPanel.Height = 68
$diagnosticPanel.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
$form.Controls.Add($diagnosticPanel)

$diagnosticLabel = New-Object System.Windows.Forms.Label
$diagnosticLabel.Text = 'Diagnostic command:'
$diagnosticLabel.Location = New-Object System.Drawing.Point(10, 7)
$diagnosticLabel.AutoSize = $true
$diagnosticPanel.Controls.Add($diagnosticLabel)

$diagnosticInput = New-Object System.Windows.Forms.TextBox
$diagnosticInput.Location = New-Object System.Drawing.Point(12, 29)
$diagnosticInput.Width = 760
$diagnosticInput.Anchor = 'Top, Left, Right'
$diagnosticPanel.Controls.Add($diagnosticInput)

$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Top'
$status.Height = 28
$status.Padding = New-Object System.Windows.Forms.Padding(10, 5, 0, 0)
$status.Text = 'READY - no checks running'
$form.Controls.Add($status)

$output = New-Object System.Windows.Forms.RichTextBox
$output.Dock = 'Fill'
$output.ReadOnly = $true
$output.WordWrap = $false
$output.Font = New-Object System.Drawing.Font('Consolas', 9)
$output.BackColor = [System.Drawing.Color]::FromArgb(24, 30, 38)
$output.ForeColor = [System.Drawing.Color]::FromArgb(225, 232, 240)
$form.Controls.Add($output)

$script:child = $null
$script:mode = ''
$script:stdoutPath = ''
$script:stderrPath = ''
$script:reportPath = ''
$script:logPath = ''
$script:stdoutOffset = 0
$script:stderrOffset = 0

function New-ConsoleButton {
    param([string]$Caption, [int]$Width = 130)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Caption
    $button.Width = $Width
    $button.Height = 30
    $button.Margin = New-Object System.Windows.Forms.Padding(4)
    return $button
}

$diagnosticButton = New-ConsoleButton 'RUN DIAGNOSTIC' 150
$diagnosticButton.Location = New-Object System.Drawing.Point(780, 27)
$diagnosticButton.Anchor = 'Top, Right'
$diagnosticPanel.Controls.Add($diagnosticButton)

$allButton = New-ConsoleButton 'RUN ALL CHECKS' 150
$buildButton = New-ConsoleButton 'BUILD' 85
$testButton = New-ConsoleButton 'RUN TESTS' 105
$artifactButton = New-ConsoleButton 'VALIDATE ARTIFACTS' 155
$guardButton = New-ConsoleButton 'TEST GUARD' 105
$reportsButton = New-ConsoleButton 'OPEN REPORTS' 120
$buttons.Controls.AddRange(@($allButton,$buildButton,$testButton,$artifactButton,$guardButton,$reportsButton))

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400

function Start-ConsoleRun {
    param([string]$Mode, [string]$DiagnosticCommand = '')
    if ($script:child -and -not $script:child.HasExited) { return }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:mode = $Mode
    $script:stdoutPath = Join-Path $logDir "stdout-$stamp.log"
    $script:stderrPath = Join-Path $logDir "stderr-$stamp.log"
    $script:logPath = Join-Path $logDir "run-$($Mode.ToLower())-$stamp.log"
    $script:reportPath = Join-Path $logDir "report-$stamp.json"
    $script:stdoutOffset = 0
    $script:stderrOffset = 0
    $output.Clear()
    $output.AppendText("Starting $Mode`r`nRepository: $root`r`nLogs: $logDir`r`n`r`n")
    Set-Content -LiteralPath $script:logPath -Value "Mode: $Mode`r`nRepository: $root" -Encoding UTF8
    $status.Text = "RUNNING - $Mode"
    foreach ($button in @($allButton,$buildButton,$testButton,$artifactButton,$guardButton,$diagnosticButton)) { $button.Enabled = $false }

    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($Mode -eq 'DIAGNOSTIC') {
        if ([string]::IsNullOrWhiteSpace($DiagnosticCommand)) {
            $status.Text = 'READY - enter a diagnostic command first'
            $output.AppendText('No diagnostic command entered. Nothing was executed.' + "`r`n")
            foreach ($button in @($allButton,$buildButton,$testButton,$artifactButton,$guardButton,$diagnosticButton)) { $button.Enabled = $true }
            return
        }
        $diagnosticScript = Join-Path $logDir "diagnostic-$stamp.ps1"
        Set-Content -LiteralPath $diagnosticScript -Value $DiagnosticCommand -Encoding UTF8
        $script:logPath = $diagnosticScript
        $argumentLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $diagnosticScript + '"'
    } else {
        $argumentLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -RepositoryRoot "' + $root + '" -RunMode ' + $Mode
    }
    try {
        $script:child = Start-Process -FilePath $powershell -ArgumentList $argumentLine -WorkingDirectory $root -PassThru -RedirectStandardOutput $script:stdoutPath -RedirectStandardError $script:stderrPath
        $timer.Start()
    }
    catch {
        $status.Text = 'FAILED TO START - see message below'
        $output.AppendText($_.Exception.Message + "`r`n")
        foreach ($button in @($allButton,$buildButton,$testButton,$artifactButton,$guardButton,$diagnosticButton)) { $button.Enabled = $true }
    }
}

$timer.Add_Tick({
    if ($script:stdoutPath -and (Test-Path -LiteralPath $script:stdoutPath)) {
        try {
            $content = [System.IO.File]::ReadAllText($script:stdoutPath)
            if ($content.Length -gt $script:stdoutOffset) {
                $output.AppendText($content.Substring($script:stdoutOffset))
                $script:stdoutOffset = $content.Length
                $output.SelectionStart = $output.TextLength
                $output.ScrollToCaret()
            }
        } catch { }
    }
    if ($script:stderrPath -and (Test-Path -LiteralPath $script:stderrPath)) {
        try {
            $content = [System.IO.File]::ReadAllText($script:stderrPath)
            if ($content.Length -gt $script:stderrOffset) {
                $output.AppendText($content.Substring($script:stderrOffset))
                $script:stderrOffset = $content.Length
                $output.SelectionStart = $output.TextLength
                $output.ScrollToCaret()
            }
        } catch { }
    }
    if ($script:child -and $script:child.HasExited) {
        $timer.Stop()
        $exitCode = $script:child.ExitCode
        $script:child.Dispose()
        $script:child = $null
        $finalStatus = if ($exitCode -eq 0) { 'PASS - run completed' } else { "FAIL - exit code $exitCode" }
        $status.Text = $finalStatus
        foreach ($button in @($allButton,$buildButton,$testButton,$artifactButton,$guardButton,$diagnosticButton)) { $button.Enabled = $true }
        $branch = (& git -C $root rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
        $commit = (& git -C $root rev-parse HEAD 2>$null | Out-String).Trim()
        $report = [ordered]@{
            schema_version = 1
            finished_at = (Get-Date).ToString('o')
            repository = $root
            branch = $branch
            commit = $commit
            mode = $script:mode
            exit_code = $exitCode
            stdout = $script:stdoutPath
            stderr = $script:stderrPath
            log = $script:logPath
        }
        $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:reportPath -Encoding UTF8
        $output.AppendText("`r`nREPORT: $script:reportPath`r`n")
    }
})

$allButton.Add_Click({ Start-ConsoleRun 'ALL' })
$buildButton.Add_Click({ Start-ConsoleRun 'BUILD' })
$testButton.Add_Click({ Start-ConsoleRun 'TEST' })
$artifactButton.Add_Click({ Start-ConsoleRun 'ARTIFACTS' })
$guardButton.Add_Click({ Start-ConsoleRun 'GUARD' })
$diagnosticButton.Add_Click({ Start-ConsoleRun 'DIAGNOSTIC' $diagnosticInput.Text })
$diagnosticInput.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $_.SuppressKeyPress = $true
        Start-ConsoleRun 'DIAGNOSTIC' $diagnosticInput.Text
    }
})
$reportsButton.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $logDir + '"') })
$form.Add_FormClosing({
    if ($script:child -and -not $script:child.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'Checks are still running. Close the console and stop the child process?',
            'Run in progress',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
        } else {
            try { $script:child.Kill() } catch { }
        }
    }
})
[void]$form.ShowDialog()
