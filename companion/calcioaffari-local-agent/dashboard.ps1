[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConfigPath = Join-Path $InstallDir "agent.json"
$TaskName = "CalcioAffari Local Agent"
$AgentVersion = "1.0.10"
$DiagnosePath = Join-Path $InstallDir "diagnose.ps1"
$script:DiagnosticProcess = $null
$script:DiagnosticOutput = $null
. (Join-Path $PSScriptRoot "common.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Enable-CalcioAffariDpiAwareness
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-AppConfig {
    if (-not (Test-Path $ConfigPath)) {
        throw "Configurazione non trovata. Esegui prima Installa-CalcioAffari.cmd."
    }
    return Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Set-StatusLabel {
    param($Label, [bool]$Ok, [string]$Success, [string]$Failure)
    $Label.Text = $(if ($Ok) { "●  $Success" } else { "●  $Failure" })
    $Label.ForeColor = $(if ($Ok) { [Drawing.Color]::FromArgb(47, 188, 112) } else { [Drawing.Color]::FromArgb(230, 88, 88) })
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "CalcioAffari Local Newsroom"
$form.Size = New-Object Drawing.Size(880, 650)
$form.MinimumSize = New-Object Drawing.Size(880, 650)
$form.StartPosition = "CenterScreen"
$form.BackColor = [Drawing.Color]::FromArgb(13, 20, 18)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font("Segoe UI", 10)
$form.MaximizeBox = $false

$eyebrow = New-Object System.Windows.Forms.Label
$eyebrow.Text = "CALCIOAFFARI · LOCAL NEWSROOM"
$eyebrow.Font = New-Object Drawing.Font("Segoe UI Semibold", 10)
$eyebrow.ForeColor = [Drawing.Color]::FromArgb(73, 210, 137)
$eyebrow.Location = New-Object Drawing.Point(28, 24)
$eyebrow.AutoSize = $true
$form.Controls.Add($eyebrow)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Motore editoriale IA"
$title.Font = New-Object Drawing.Font("Segoe UI Semibold", 24)
$title.Location = New-Object Drawing.Point(24, 50)
$title.Size = New-Object Drawing.Size(500, 48)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Stato del collegamento tra WordPress e Qwen3 sulla workstation."
$subtitle.ForeColor = [Drawing.Color]::FromArgb(176, 190, 184)
$subtitle.Location = New-Object Drawing.Point(29, 101)
$subtitle.Size = New-Object Drawing.Size(700, 25)
$form.Controls.Add($subtitle)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object Drawing.Point(30, 142)
$statusPanel.Size = New-Object Drawing.Size(804, 122)
$statusPanel.BackColor = [Drawing.Color]::FromArgb(24, 35, 31)
$form.Controls.Add($statusPanel)

$agentStatus = New-Object System.Windows.Forms.Label
$agentStatus.Location = New-Object Drawing.Point(22, 19)
$agentStatus.Size = New-Object Drawing.Size(360, 28)
$agentStatus.Font = New-Object Drawing.Font("Segoe UI Semibold", 11)
$statusPanel.Controls.Add($agentStatus)

$ollamaStatus = New-Object System.Windows.Forms.Label
$ollamaStatus.Location = New-Object Drawing.Point(22, 61)
$ollamaStatus.Size = New-Object Drawing.Size(360, 28)
$ollamaStatus.Font = New-Object Drawing.Font("Segoe UI Semibold", 11)
$statusPanel.Controls.Add($ollamaStatus)

$siteStatus = New-Object System.Windows.Forms.Label
$siteStatus.Location = New-Object Drawing.Point(420, 19)
$siteStatus.Size = New-Object Drawing.Size(360, 28)
$siteStatus.Font = New-Object Drawing.Font("Segoe UI Semibold", 11)
$statusPanel.Controls.Add($siteStatus)

$modelStatus = New-Object System.Windows.Forms.Label
$modelStatus.Location = New-Object Drawing.Point(420, 61)
$modelStatus.Size = New-Object Drawing.Size(360, 28)
$modelStatus.Font = New-Object Drawing.Font("Segoe UI Semibold", 11)
$statusPanel.Controls.Add($modelStatus)

$detailsLabel = New-Object System.Windows.Forms.Label
$detailsLabel.Text = "Diagnostica"
$detailsLabel.Font = New-Object Drawing.Font("Segoe UI Semibold", 12)
$detailsLabel.Location = New-Object Drawing.Point(29, 285)
$detailsLabel.AutoSize = $true
$form.Controls.Add($detailsLabel)

$details = New-Object System.Windows.Forms.TextBox
$details.Location = New-Object Drawing.Point(30, 315)
$details.Size = New-Object Drawing.Size(804, 180)
$details.Multiline = $true
$details.ReadOnly = $true
$details.ScrollBars = "Vertical"
$details.BackColor = [Drawing.Color]::FromArgb(18, 27, 24)
$details.ForeColor = [Drawing.Color]::FromArgb(216, 225, 221)
$details.BorderStyle = "FixedSingle"
$details.Font = New-Object Drawing.Font("Consolas", 10)
$form.Controls.Add($details)

function New-ActionButton {
    param([string]$Text, [int]$X, [int]$Width = 145)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object Drawing.Point($X, 520)
    $button.Size = New-Object Drawing.Size($Width, 38)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(57, 91, 76)
    $button.BackColor = [Drawing.Color]::FromArgb(30, 48, 40)
    $button.ForeColor = [Drawing.Color]::White
    return $button
}

$refreshButton = New-ActionButton "Aggiorna stato" 30
$restartButton = New-ActionButton "Riavvia agente" 187
$wordpressButton = New-ActionButton "Apri WordPress" 344
$repairButton = New-ActionButton "Ripara" 501
$logButton = New-ActionButton "Esporta diagnosi" 658 176
$form.Controls.AddRange(@($refreshButton, $restartButton, $wordpressButton, $repairButton, $logButton))

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "v$AgentVersion · Credenziale cifrata per questo utente Windows · Nessun servizio IA cloud"
$footer.ForeColor = [Drawing.Color]::FromArgb(125, 145, 136)
$footer.Location = New-Object Drawing.Point(30, 580)
$footer.Size = New-Object Drawing.Size(800, 24)
$form.Controls.Add($footer)

function Apply-DiagnosticResult {
    param($Result)
    Set-StatusLabel $agentStatus ($Result.task_state -ne "Assente") "Agente automatico: $($Result.task_state)" "Agente automatico non attivo"
    Set-StatusLabel $ollamaStatus ([bool]$Result.ollama_online) "Ollama collegato" "Ollama non raggiungibile"
    Set-StatusLabel $modelStatus ([bool]$Result.model_ready) "Modello Qwen3 pronto" "Modello Qwen3 assente"
    Set-StatusLabel $siteStatus ([bool]$Result.site_online) "WordPress collegato" ([string]$Result.site_state)
    $lines = New-Object System.Collections.Generic.List[string]
    if ($Result.health) {
        $lines.Add("Plugin WordPress: v$($Result.health.version)")
        if ($Result.health.minimum_agent_version) { $lines.Add("Versione minima app: $($Result.health.minimum_agent_version)") }
        $lines.Add("Modalità pubblicazione: $($Result.health.publication_mode)")
        $lines.Add("Fonti attive: $($Result.health.sources_enabled)")
        $lines.Add("Ultimo contatto agente: $($Result.health.last_agent_seen)")
        if ($Result.health.last_ingest_at) {
            $lastIngest = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Result.health.last_ingest_at).LocalDateTime
            $lines.Add("Ultima raccolta fonti: $($lastIngest.ToString('dd/MM/yyyy HH:mm'))")
        }
        $lines.Add("")
        $lines.Add("Coda WordPress:")
        foreach ($property in $Result.health.jobs.PSObject.Properties) { $lines.Add(("  {0}: {1}" -f $property.Name, $property.Value)) }
        if ($Result.health.recent_errors -and @($Result.health.recent_errors).Count -gt 0) {
            $lines.Add("")
            $lines.Add("Ultimi problemi editoriali:")
            foreach ($item in @($Result.health.recent_errors)) {
                $lines.Add(("  Job #{0} · {1} · tentativo {2}: {3}" -f $item.job_id, $item.status, $item.attempt, $item.message))
            }
        }
    }
    foreach ($message in @($Result.details)) { if ($message) { $lines.Add([string]$message) } }
    if ($lines.Count -eq 0) { $lines.Add("Tutti i controlli sono stati completati.") }
    $details.Lines = $lines.ToArray()
}

function Refresh-Dashboard {
    if ($script:DiagnosticProcess -and -not $script:DiagnosticProcess.HasExited) { return }
    if (-not (Test-Path $DiagnosePath)) {
        $details.Text = "Diagnostica mancante. Usa Ripara oppure reinstalla l'applicazione."
        return
    }
    $script:DiagnosticOutput = Join-Path $env:TEMP ("calcioaffari-diagnostic-" + [Guid]::NewGuid().ToString("N") + ".json")
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $PSHOME "powershell.exe"
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$DiagnosePath`" -OutputPath `"$script:DiagnosticOutput`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $script:DiagnosticProcess = [Diagnostics.Process]::Start($startInfo)
    $refreshButton.Enabled = $false
    $details.Text = "Controlli in corso…"
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $diagnosticTimer.Start()
}

$diagnosticTimer = New-Object System.Windows.Forms.Timer
$diagnosticTimer.Interval = 250
$diagnosticTimer.Add_Tick({
    if ($script:DiagnosticOutput -and (Test-Path $script:DiagnosticOutput)) {
        try {
            $result = Get-Content $script:DiagnosticOutput -Raw -Encoding UTF8 | ConvertFrom-Json
            Apply-DiagnosticResult $result
            Remove-Item $script:DiagnosticOutput -Force -ErrorAction SilentlyContinue
            $diagnosticTimer.Stop()
            $refreshButton.Enabled = $true
            $form.Cursor = [System.Windows.Forms.Cursors]::Default
            if ($script:DiagnosticProcess) { try { $script:DiagnosticProcess.Dispose() } catch { }; $script:DiagnosticProcess = $null }
        }
        catch {
            if ($script:DiagnosticProcess -and $script:DiagnosticProcess.HasExited) {
                $diagnosticTimer.Stop()
                $refreshButton.Enabled = $true
                $form.Cursor = [System.Windows.Forms.Cursors]::Default
                $details.Text = "La diagnostica ha prodotto dati illeggibili. Usa Esporta diagnosi per raccogliere i log."
            }
        }
    }
    elseif ($script:DiagnosticProcess -and $script:DiagnosticProcess.HasExited) {
        $diagnosticTimer.Stop()
        $refreshButton.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $details.Text = "La diagnostica si è arrestata in modo inatteso. Usa Esporta diagnosi per raccogliere i log."
        if ($script:DiagnosticProcess) { try { $script:DiagnosticProcess.Dispose() } catch { }; $script:DiagnosticProcess = $null }
    }
})

$refreshButton.Add_Click({ Refresh-Dashboard })
$restartButton.Add_Click({
    try {
        Stop-CalcioAffariScheduledTask -Name $TaskName | Out-Null
        Start-Sleep -Milliseconds 600
        Start-CalcioAffariScheduledTask -Name $TaskName
        Refresh-Dashboard
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "CalcioAffari", "OK", "Warning") | Out-Null }
})
$wordpressButton.Add_Click({
    try {
        $config = Get-AppConfig
        Start-Process ($config.site_url.TrimEnd('/') + "/wp-admin/admin.php?page=calcioaffari-news-engine")
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "CalcioAffari") | Out-Null }
})
$repairButton.Add_Click({
    $setupPath = Join-Path $InstallDir "setup-gui.ps1"
    Start-CalcioAffariHiddenPowerShell -InstallDir $InstallDir -ScriptPath $setupPath | Out-Null
    $form.Close()
})
$logButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "Archivio ZIP (*.zip)|*.zip"
    $dialog.FileName = "CalcioAffari-diagnostica-$((Get-Date).ToString('yyyyMMdd-HHmm')).zip"
    if ($dialog.ShowDialog() -eq "OK") {
        $staging = Join-Path $env:TEMP ("calcioaffari-support-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        foreach ($name in @("agent.log", "agent.previous.log", "install.log", "upgrade.log", "connection-paused.txt", "version.json")) {
            $source = Join-Path $InstallDir $name
            if (Test-Path $source) {
                $safeText = Protect-CalcioAffariSecretText ([IO.File]::ReadAllText($source))
                [IO.File]::WriteAllText((Join-Path $staging $name), $safeText, (New-Object Text.UTF8Encoding($false)))
            }
        }
        if (Test-Path $ConfigPath) {
            $safeConfig = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $safeConfig | ConvertTo-Json | Set-Content (Join-Path $staging "agent-sanitized.json") -Encoding UTF8
        }
        "Windows: $([Environment]::OSVersion.VersionString)`r`nPowerShell: $($PSVersionTable.PSVersion)`r`nApp: $AgentVersion" | Set-Content (Join-Path $staging "system.txt") -Encoding UTF8
        Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $dialog.FileName -Force
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("Diagnostica salvata. Il codice di collegamento non è incluso.", "CalcioAffari", "OK", "Information") | Out-Null
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000
$timer.Add_Tick({ Refresh-Dashboard })
$timer.Start()
$form.Add_Shown({ Refresh-Dashboard })
[void]$form.ShowDialog()
$timer.Stop()
$diagnosticTimer.Stop()
if ($script:DiagnosticProcess -and -not $script:DiagnosticProcess.HasExited) {
    & taskkill.exe /PID $script:DiagnosticProcess.Id /T /F 2>$null | Out-Null
}
if ($script:DiagnosticOutput) { Remove-Item $script:DiagnosticOutput -Force -ErrorAction SilentlyContinue }
$timer.Dispose()
$diagnosticTimer.Dispose()
