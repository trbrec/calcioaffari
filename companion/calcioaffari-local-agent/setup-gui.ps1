[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$BackendPath = Join-Path $PSScriptRoot "install.ps1"
$AgentVersion = "1.1.2"
$script:CurrentProcess = $null
$script:StatusPath = $null
$script:PairingCodePath = $null
$script:CurrentAction = ""
. (Join-Path $PSScriptRoot "common.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Enable-CalcioAffariDpiAwareness
[System.Windows.Forms.Application]::EnableVisualStyles()

$green = [Drawing.Color]::FromArgb(61, 211, 139)
$dark = [Drawing.Color]::FromArgb(12, 18, 16)
$panel = [Drawing.Color]::FromArgb(23, 34, 30)
$muted = [Drawing.Color]::FromArgb(171, 187, 180)
$red = [Drawing.Color]::FromArgb(235, 92, 92)

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height = 28, [float]$Size = 10, [bool]$Bold = $false)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($Width, $Height)
    $style = $(if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular })
    $label.Font = New-Object Drawing.Font("Segoe UI", $Size, $style)
    $label.ForeColor = [Drawing.Color]::White
    return $label
}

function Export-SetupLog {
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "Archivio diagnostico ZIP (*.zip)|*.zip"
    $dialog.FileName = "CalcioAffari-log-$((Get-Date).ToString('yyyyMMdd-HHmmss')).zip"
    $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dialog.ShowDialog() -ne "OK") { return }

    $staging = Join-Path $env:TEMP ("calcioaffari-setup-log-" + [Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        foreach ($name in @("install.log", "upgrade.log", "agent.log", "agent.previous.log", "connection-paused.txt", "agent.json", "version.json")) {
            $source = Join-Path $InstallDir $name
            if (Test-Path $source) {
                $safeText = Protect-CalcioAffariSecretText ([IO.File]::ReadAllText($source))
                [IO.File]::WriteAllText((Join-Path $staging $name), $safeText, (New-Object Text.UTF8Encoding($false)))
            }
        }
        if ($script:StatusPath -and (Test-Path $script:StatusPath)) {
            $safeStatus = Protect-CalcioAffariSecretText ([IO.File]::ReadAllText($script:StatusPath))
            [IO.File]::WriteAllText((Join-Path $staging "current-status.json"), $safeStatus, (New-Object Text.UTF8Encoding($false)))
        }
        $processState = if (-not $script:CurrentProcess) { "nessun processo" } elseif ($script:CurrentProcess.HasExited) { "terminato: $($script:CurrentProcess.ExitCode)" } else { "in esecuzione: PID $($script:CurrentProcess.Id)" }
        $session = @(
            "Data: $((Get-Date).ToString('o'))"
            "App: $AgentVersion"
            "Windows: $([Environment]::OSVersion.VersionString)"
            "PowerShell: $($PSVersionTable.PSVersion)"
            "Azione: $($script:CurrentAction)"
            "Processo: $processState"
            "Messaggio: $(Protect-CalcioAffariSecretText $detailLabel.Text)"
        ) -join "`r`n"
        [IO.File]::WriteAllText((Join-Path $staging "sessione-corrente.txt"), $session, (New-Object Text.UTF8Encoding($false)))
        Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $dialog.FileName -Force
        [System.Windows.Forms.MessageBox]::Show("Log esportato. Il codice di collegamento è stato rimosso automaticamente.", "CalcioAffari", "OK", "Information") | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Esportazione non riuscita: $($_.Exception.Message)", "CalcioAffari", "OK", "Warning") | Out-Null
    }
    finally { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
}

function Set-State {
    param($Label, [string]$Text, [ValidateSet("idle", "working", "ok", "error")][string]$State)
    $prefix = $(if ($State -eq "idle") { [char]0x25CB } else { [char]0x25CF })
    $Label.Text = "$prefix  $Text"
    $Label.ForeColor = switch ($State) {
        "working" { [Drawing.Color]::FromArgb(245, 194, 66) }
        "ok" { $green }
        "error" { $red }
        default { $muted }
    }
}

function Set-Busy {
    param([bool]$Busy)
    $prepareButton.Enabled = -not $Busy
    $connectButton.Enabled = (-not $Busy) -and $sitePanel.Enabled
    $pairingCodeBox.Enabled = -not $Busy
    $openWordPressButton.Enabled = -not $Busy
    $cancelButton.Enabled = $Busy
}

function Stop-BackendTree {
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        & taskkill.exe /PID $script:CurrentProcess.Id /T /F 2>$null | Out-Null
        try { $script:CurrentProcess.WaitForExit(3000) | Out-Null } catch { }
    }
}

function Complete-BackendFailure {
    param([string]$Message)
    $pollTimer.Stop()
    Set-Busy $false
    $progress.Style = "Continuous"
    if ($script:CurrentAction -eq "Prepare") {
        Set-State $engineState "Preparazione non completata" "error"
        Set-State $modelState "Modello non pronto" "error"
    }
    else { Set-State $siteState "Collegamento non completato" "error" }
    $detailLabel.Text = $Message
    if ($script:CurrentProcess) { try { $script:CurrentProcess.Dispose() } catch { }; $script:CurrentProcess = $null }
    if ($script:StatusPath) { Remove-Item $script:StatusPath -Force -ErrorAction SilentlyContinue }
    if ($script:PairingCodePath) { Remove-Item $script:PairingCodePath -Force -ErrorAction SilentlyContinue }
    [System.Windows.Forms.MessageBox]::Show($Message, "CalcioAffari", "OK", "Warning") | Out-Null
}

function Start-Backend {
    param([ValidateSet("Prepare", "Connect")][string]$Action)
    if (-not (Test-Path $BackendPath)) {
        [System.Windows.Forms.MessageBox]::Show("Componente di installazione mancante. Riesegui il Setup.", "CalcioAffari", "OK", "Error") | Out-Null
        return
    }
    $script:CurrentAction = $Action
    $script:StatusPath = Join-Path $env:TEMP ("calcioaffari-status-" + [Guid]::NewGuid().ToString("N") + ".json")
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
        "-File", ('"' + $BackendPath + '"'), "-Phase", $Action,
        "-StatusPath", ('"' + $script:StatusPath + '"')
    )
    if ($Action -eq "Connect") {
        if (-not $pairingCodeBox.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show("Inserisci il codice generato in WordPress > CalcioAffari.", "CalcioAffari", "OK", "Information") | Out-Null
            return
        }
        $script:PairingCodePath = Join-Path $env:TEMP ("calcioaffari-pairing-" + [Guid]::NewGuid().ToString("N") + ".txt")
        $secureInput = ConvertTo-SecureString $pairingCodeBox.Text.Trim() -AsPlainText -Force
        $encryptedInput = ConvertFrom-SecureString $secureInput
        [IO.File]::WriteAllText($script:PairingCodePath, $encryptedInput, (New-Object Text.UTF8Encoding($false)))
        $arguments += @(
            "-PairingCodePath", ('"' + $script:PairingCodePath + '"')
        )
    }
    $progress.Style = "Marquee"
    $progress.MarqueeAnimationSpeed = 28
    $progress.Value = 0
    $detailLabel.Text = "Avvio della procedura…"
    Set-Busy $true
    if ($Action -eq "Prepare") {
        Set-State $engineState "Preparazione del motore locale" "working"
        Set-State $modelState "Verifica di Qwen3" "working"
    }
    else { Set-State $siteState "Verifica del collegamento" "working" }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Join-Path $PSHOME "powershell.exe")
    $startInfo.Arguments = ($arguments -join " ")
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.CreateNoWindow = $true
    $startInfo.UseShellExecute = $false
    $script:CurrentProcess = [Diagnostics.Process]::Start($startInfo)
    $pollTimer.Start()
}

function Initialize-ExistingInstallation {
    foreach ($name in @("install.log", "upgrade.log", "agent.log", "agent.previous.log")) {
        Protect-CalcioAffariLogFile -Path (Join-Path $InstallDir $name)
    }
    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 2
        $models = @($tags.models | ForEach-Object { [string]$_.name })
        if ($models -contains "qwen3:14b" -or $models -contains "qwen3:14b:latest") {
            Set-State $engineState "Ollama pronto" "ok"
            Set-State $modelState "Qwen3 pronto" "ok"
            $sitePanel.Enabled = $true
            $connectButton.Enabled = $true
            $detailLabel.Text = "Motore locale già presente: non verrà scaricato di nuovo."
        }
    }
    catch { }
    if ((Test-Path (Join-Path $InstallDir "agent.json")) -and (Test-Path (Join-Path $InstallDir "agent-token.txt"))) {
        $sitePanel.Enabled = $true
        Set-State $siteState "Collegamento salvato; verifica dal pannello" "idle"
        $dashboardButton.Enabled = $true
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "CalcioAffari Local Newsroom - Configurazione"
$form.Size = New-Object Drawing.Size(820, 690)
$form.MinimumSize = New-Object Drawing.Size(820, 690)
$form.StartPosition = "CenterScreen"
$form.BackColor = $dark
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font("Segoe UI", 10)
$form.MaximizeBox = $false

$eyebrow = New-Label "CALCIOAFFARI - LOCAL NEWSROOM" 30 24 500 26 10 $true
$eyebrow.ForeColor = $green
$form.Controls.Add($eyebrow)
$form.Controls.Add((New-Label "Configurazione guidata" 27 53 600 48 24 $true))
$subtitle = New-Label "Nessun comando da digitare: segui i due passaggi e controlla i semafori." 31 103 720 28 10 $false
$subtitle.ForeColor = $muted
$form.Controls.Add($subtitle)

$localPanel = New-Object System.Windows.Forms.Panel
$localPanel.Location = New-Object Drawing.Point(30, 145)
$localPanel.Size = New-Object Drawing.Size(744, 180)
$localPanel.BackColor = $panel
$form.Controls.Add($localPanel)
$localPanel.Controls.Add((New-Label "1" 20 18 30 30 13 $true))
$localPanel.Controls.Add((New-Label "Prepara il motore IA locale" 56 17 500 32 14 $true))
$engineState = New-Label "○  Ollama da verificare" 57 62 610 28 10 $true
$engineState.ForeColor = $muted
$localPanel.Controls.Add($engineState)
$modelState = New-Label "○  Qwen3 da verificare" 57 96 610 28 10 $true
$modelState.ForeColor = $muted
$localPanel.Controls.Add($modelState)
$prepareButton = New-Object System.Windows.Forms.Button
$prepareButton.Text = "PREPARA MOTORE IA"
$prepareButton.Location = New-Object Drawing.Point(530, 125)
$prepareButton.Size = New-Object Drawing.Size(190, 38)
$prepareButton.FlatStyle = "Flat"
$prepareButton.BackColor = [Drawing.Color]::FromArgb(36, 95, 66)
$prepareButton.ForeColor = [Drawing.Color]::White
$prepareButton.FlatAppearance.BorderColor = $green
$localPanel.Controls.Add($prepareButton)

$sitePanel = New-Object System.Windows.Forms.Panel
$sitePanel.Location = New-Object Drawing.Point(30, 340)
$sitePanel.Size = New-Object Drawing.Size(744, 190)
$sitePanel.BackColor = $panel
$sitePanel.Enabled = $false
$form.Controls.Add($sitePanel)
$sitePanel.Controls.Add((New-Label "2" 20 18 30 30 13 $true))
$sitePanel.Controls.Add((New-Label "Collega calcioaffari.it" 56 17 500 32 14 $true))
$pairingLabel = New-Label "Codice di collegamento generato nel pannello CalcioAffari" 57 58 638 22 9 $false
$pairingLabel.ForeColor = $muted
$sitePanel.Controls.Add($pairingLabel)
$pairingCodeBox = New-Object System.Windows.Forms.TextBox
$pairingCodeBox.Location = New-Object Drawing.Point(57, 82)
$pairingCodeBox.Size = New-Object Drawing.Size(638, 28)
$pairingCodeBox.UseSystemPasswordChar = $true
$sitePanel.Controls.Add($pairingCodeBox)
$openWordPressButton = New-Object System.Windows.Forms.Button
$openWordPressButton.Text = "APRI WORDPRESS"
$openWordPressButton.Location = New-Object Drawing.Point(57, 132)
$openWordPressButton.Size = New-Object Drawing.Size(165, 38)
$sitePanel.Controls.Add($openWordPressButton)
$siteState = New-Label "○  Collegamento non configurato" 240 137 280 28 10 $true
$siteState.ForeColor = $muted
$sitePanel.Controls.Add($siteState)
$connectButton = New-Object System.Windows.Forms.Button
$connectButton.Text = "COLLEGA IL SITO"
$connectButton.Location = New-Object Drawing.Point(530, 132)
$connectButton.Size = New-Object Drawing.Size(165, 38)
$connectButton.FlatStyle = "Flat"
$connectButton.BackColor = [Drawing.Color]::FromArgb(36, 95, 66)
$connectButton.ForeColor = [Drawing.Color]::White
$connectButton.FlatAppearance.BorderColor = $green
$sitePanel.Controls.Add($connectButton)

$detailLabel = New-Label "Pronto per iniziare." 31 552 640 28 10 $false
$detailLabel.ForeColor = $muted
$form.Controls.Add($detailLabel)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(30, 584)
$progress.Size = New-Object Drawing.Size(744, 14)
$progress.Style = "Continuous"
$form.Controls.Add($progress)
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Annulla"
$cancelButton.Location = New-Object Drawing.Point(30, 615)
$cancelButton.Size = New-Object Drawing.Size(105, 32)
$cancelButton.Enabled = $false
$form.Controls.Add($cancelButton)
$exportLogButton = New-Object System.Windows.Forms.Button
$exportLogButton.Text = "ESPORTA LOG"
$exportLogButton.Location = New-Object Drawing.Point(150, 610)
$exportLogButton.Size = New-Object Drawing.Size(155, 38)
$exportLogButton.FlatStyle = "Flat"
$exportLogButton.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(57, 91, 76)
$exportLogButton.BackColor = [Drawing.Color]::FromArgb(30, 48, 40)
$exportLogButton.ForeColor = [Drawing.Color]::White
$form.Controls.Add($exportLogButton)
$dashboardButton = New-Object System.Windows.Forms.Button
$dashboardButton.Text = "APRI PANNELLO"
$dashboardButton.Location = New-Object Drawing.Point(595, 610)
$dashboardButton.Size = New-Object Drawing.Size(179, 38)
$dashboardButton.Enabled = $false
$dashboardButton.FlatStyle = "Flat"
$dashboardButton.BackColor = [Drawing.Color]::FromArgb(36, 95, 66)
$dashboardButton.ForeColor = [Drawing.Color]::White
$form.Controls.Add($dashboardButton)

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 500
$pollTimer.Add_Tick({
    if ($script:StatusPath -and (Test-Path $script:StatusPath)) {
        try {
            $status = Get-Content $script:StatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $detailLabel.Text = [string]$status.message
            if ($status.indeterminate) {
                $progress.Style = "Marquee"
                $progress.MarqueeAnimationSpeed = 28
            }
            else {
                $progress.Style = "Continuous"
                $progress.Value = [Math]::Max(0, [Math]::Min(100, [int]$status.percent))
            }
            if ($status.done) {
                $pollTimer.Stop()
                Set-Busy $false
                $progress.Style = "Continuous"
                $progress.Value = 100
                if ($status.success) {
                    if ($script:CurrentAction -eq "Prepare") {
                        Set-State $engineState "Ollama pronto" "ok"
                        Set-State $modelState "Qwen3 pronto" "ok"
                        $sitePanel.Enabled = $true
                        $connectButton.Enabled = $true
                        $detailLabel.Text = "Motore locale pronto. Ora collega il sito."
                    }
                    else {
                        Set-State $siteState "calcioaffari.it collegato" "ok"
                        $dashboardButton.Enabled = $true
                        $detailLabel.Text = "Configurazione completata: il sistema è operativo."
                        $pairingCodeBox.Text = ""
                    }
                }
                else {
                    if ($script:CurrentAction -eq "Prepare") {
                        Set-State $engineState "Preparazione non completata" "error"
                        Set-State $modelState "Modello non pronto" "error"
                    }
                    else { Set-State $siteState "Collegamento non completato" "error" }
                    [System.Windows.Forms.MessageBox]::Show([string]$status.message, "CalcioAffari", "OK", "Warning") | Out-Null
                }
                Remove-Item $script:StatusPath -Force -ErrorAction SilentlyContinue
                if ($script:PairingCodePath) { Remove-Item $script:PairingCodePath -Force -ErrorAction SilentlyContinue }
                if ($script:CurrentProcess) { try { $script:CurrentProcess.Dispose() } catch { }; $script:CurrentProcess = $null }
            }
        }
        catch {
            if ($script:CurrentProcess -and $script:CurrentProcess.HasExited) {
                Complete-BackendFailure "La procedura ha prodotto uno stato illeggibile. Riapri l'applicazione e usa Ripara."
            }
        }
    }
    elseif ($script:CurrentProcess -and $script:CurrentProcess.HasExited) {
        Complete-BackendFailure ("La procedura si è arrestata in modo inatteso (codice {0}). Riapri l'applicazione e usa Ripara; i dettagli sono nel log di installazione." -f $script:CurrentProcess.ExitCode)
    }
})

$prepareButton.Add_Click({ Start-Backend "Prepare" })
$connectButton.Add_Click({ Start-Backend "Connect" })
$openWordPressButton.Add_Click({ Start-Process "https://calcioaffari.it/wp-admin/admin.php?page=calcioaffari-news-engine" })
$exportLogButton.Add_Click({ Export-SetupLog })
$cancelButton.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show("Interrompere l'operazione in corso?", "CalcioAffari", "YesNo", "Question")
        if ($answer -eq "Yes") {
            Stop-BackendTree
            $pollTimer.Stop()
            Set-Busy $false
            $detailLabel.Text = "Operazione interrotta. Puoi riprovare."
            if ($script:StatusPath) { Remove-Item $script:StatusPath -Force -ErrorAction SilentlyContinue }
            if ($script:PairingCodePath) { Remove-Item $script:PairingCodePath -Force -ErrorAction SilentlyContinue }
            if ($script:CurrentProcess) { try { $script:CurrentProcess.Dispose() } catch { }; $script:CurrentProcess = $null }
        }
    }
})
$dashboardButton.Add_Click({
    $dashboard = Join-Path $InstallDir "dashboard.ps1"
    if (Test-Path $dashboard) {
        Start-CalcioAffariHiddenPowerShell -InstallDir $InstallDir -ScriptPath $dashboard | Out-Null
        $form.Close()
    }
})
$form.Add_FormClosing({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show("La configurazione è ancora in corso. Vuoi davvero chiudere?", "CalcioAffari", "YesNo", "Question")
        if ($answer -ne "Yes") { $_.Cancel = $true }
        else { Stop-BackendTree }
    }
})
$form.Add_Shown({ Initialize-ExistingInstallation })

[void]$form.ShowDialog()
$pollTimer.Stop()
$pollTimer.Dispose()
