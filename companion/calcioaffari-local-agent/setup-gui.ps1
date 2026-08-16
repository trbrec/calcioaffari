[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$BackendPath = Join-Path $PSScriptRoot "install.ps1"
$AgentVersion = "0.8.1"
$script:CurrentProcess = $null
$script:StatusPath = $null
$script:CredentialPath = $null
$script:CurrentAction = ""

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
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

function Set-State {
    param($Label, [string]$Text, [ValidateSet("idle", "working", "ok", "error")][string]$State)
    $prefix = $(if ($State -eq "idle") { "○" } else { "●" })
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
    $userBox.Enabled = -not $Busy
    $passwordBox.Enabled = -not $Busy
    $cancelButton.Enabled = $Busy
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
        if (-not $userBox.Text.Trim() -or -not $passwordBox.Text) {
            [System.Windows.Forms.MessageBox]::Show("Inserisci utente WordPress e password applicazione.", "CalcioAffari", "OK", "Information") | Out-Null
            return
        }
        $script:CredentialPath = Join-Path $env:TEMP ("calcioaffari-credential-" + [Guid]::NewGuid().ToString("N") + ".txt")
        ConvertTo-SecureString $passwordBox.Text -AsPlainText -Force | ConvertFrom-SecureString | Set-Content $script:CredentialPath -Encoding UTF8
        $arguments += @(
            "-WordPressUser", ('"' + $userBox.Text.Trim().Replace('"', '') + '"'),
            "-CredentialPath", ('"' + $script:CredentialPath + '"')
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

$form = New-Object System.Windows.Forms.Form
$form.Text = "CalcioAffari Local Newsroom · Configurazione"
$form.Size = New-Object Drawing.Size(820, 690)
$form.MinimumSize = New-Object Drawing.Size(820, 690)
$form.StartPosition = "CenterScreen"
$form.BackColor = $dark
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font("Segoe UI", 10)
$form.MaximizeBox = $false

$eyebrow = New-Label "CALCIOAFFARI · LOCAL NEWSROOM" 30 24 500 26 10 $true
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
$userLabel = New-Label "Utente WordPress dedicato" 57 58 260 22 9 $false
$userLabel.ForeColor = $muted
$sitePanel.Controls.Add($userLabel)
$userBox = New-Object System.Windows.Forms.TextBox
$userBox.Location = New-Object Drawing.Point(57, 82)
$userBox.Size = New-Object Drawing.Size(260, 28)
$sitePanel.Controls.Add($userBox)
$passwordLabel = New-Label "Password applicazione (non quella principale)" 335 58 350 22 9 $false
$passwordLabel.ForeColor = $muted
$sitePanel.Controls.Add($passwordLabel)
$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.Location = New-Object Drawing.Point(335, 82)
$passwordBox.Size = New-Object Drawing.Size(360, 28)
$passwordBox.UseSystemPasswordChar = $true
$sitePanel.Controls.Add($passwordBox)
$siteState = New-Label "○  Collegamento non configurato" 57 130 410 28 10 $true
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
                        $passwordBox.Text = ""
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
                if ($script:CredentialPath) { Remove-Item $script:CredentialPath -Force -ErrorAction SilentlyContinue }
            }
        }
        catch { }
    }
})

$prepareButton.Add_Click({ Start-Backend "Prepare" })
$connectButton.Add_Click({ Start-Backend "Connect" })
$cancelButton.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show("Interrompere l'operazione in corso?", "CalcioAffari", "YesNo", "Question")
        if ($answer -eq "Yes") {
            $script:CurrentProcess.Kill()
            $pollTimer.Stop()
            Set-Busy $false
            $detailLabel.Text = "Operazione interrotta. Puoi riprovare."
        }
    }
})
$dashboardButton.Add_Click({
    $dashboard = Join-Path $InstallDir "dashboard.ps1"
    if (Test-Path $dashboard) {
        Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dashboard`""
        $form.Close()
    }
})
$form.Add_FormClosing({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show("La configurazione è ancora in corso. Vuoi davvero chiudere?", "CalcioAffari", "YesNo", "Question")
        if ($answer -ne "Yes") { $_.Cancel = $true }
    }
})

[void]$form.ShowDialog()
$pollTimer.Stop()
$pollTimer.Dispose()
