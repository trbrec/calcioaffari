[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$InstallDir = Join-Path $env:LOCALAPPDATA "CalcioAffari"
$ConfigPath = Join-Path $InstallDir "agent.json"
$SecretPath = Join-Path $InstallDir "application-password.txt"
$TaskName = "CalcioAffari Local Agent"
$AgentVersion = "0.8.0"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-Runtime {
    if (-not (Test-Path $ConfigPath) -or -not (Test-Path $SecretPath)) {
        throw "Configurazione non trovata. Esegui prima Installa-CalcioAffari.cmd."
    }
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $securePassword = Get-Content $SecretPath -Raw -Encoding UTF8 | ConvertTo-SecureString
    $credential = New-Object System.Management.Automation.PSCredential ([string]$config.wordpress_user, $securePassword)
    $plainPassword = $credential.GetNetworkCredential().Password
    $basicValue = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($config.wordpress_user):$plainPassword"))
    return @{ Config = $config; Authorization = "Basic $basicValue" }
}

function Get-OllamaState {
    param($Config)
    try {
        $tags = Invoke-RestMethod -Uri ($Config.ollama_url.TrimEnd('/') + "/api/tags") -Method Get -TimeoutSec 5
        $models = @($tags.models | ForEach-Object { [string]$_.name })
        $present = $models -contains ([string]$Config.model) -or $models -contains (([string]$Config.model) + ":latest")
        return @{ Online = $true; Model = $present; Names = $models }
    }
    catch { return @{ Online = $false; Model = $false; Names = @() } }
}

function Get-SiteHealth {
    param($Runtime)
    $uri = $Runtime.Config.site_url.TrimEnd('/') + "/wp-json/calcioaffari/v1/health"
    return Invoke-RestMethod -Uri $uri -Method Get -Headers @{ Authorization = $Runtime.Authorization; "User-Agent" = "CalcioAffari-Dashboard/$AgentVersion" } -TimeoutSec 20
}

function Get-TaskState {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        return [string]$task.State
    }
    catch {
        & schtasks.exe /Query /TN $TaskName 2>$null | Out-Null
        return $(if ($LASTEXITCODE -eq 0) { "Presente" } else { "Assente" })
    }
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
$logButton = New-ActionButton "Apri log" 658 176
$form.Controls.AddRange(@($refreshButton, $restartButton, $wordpressButton, $repairButton, $logButton))

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "v$AgentVersion · Credenziale cifrata per questo utente Windows · Nessun servizio IA cloud"
$footer.ForeColor = [Drawing.Color]::FromArgb(125, 145, 136)
$footer.Location = New-Object Drawing.Point(30, 580)
$footer.Size = New-Object Drawing.Size(800, 24)
$form.Controls.Add($footer)

function Refresh-Dashboard {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $runtime = Get-Runtime
        $taskState = Get-TaskState
        $taskOk = $taskState -notin @("Assente", "Disabled")
        Set-StatusLabel $agentStatus $taskOk "Agente automatico: $taskState" "Agente automatico non attivo"

        $ollama = Get-OllamaState $runtime.Config
        Set-StatusLabel $ollamaStatus $ollama.Online "Ollama collegato" "Ollama non raggiungibile"
        Set-StatusLabel $modelStatus $ollama.Model "Modello $($runtime.Config.model) pronto" "Modello $($runtime.Config.model) assente"

        $lines.Add("Sito: $($runtime.Config.site_url)")
        $lines.Add("Workstation: $($runtime.Config.worker_name)")
        $lines.Add("Controllo coda: ogni $($runtime.Config.poll_seconds) secondi")
        $lines.Add("")

        try {
            $health = Get-SiteHealth $runtime
            Set-StatusLabel $siteStatus $true "WordPress collegato" ""
            $lines.Add("Modalità pubblicazione: $($health.publication_mode)")
            $lines.Add("Fonti attive: $($health.sources_enabled)")
            $lines.Add("Ultimo contatto agente: $($health.last_agent_seen)")
            $lines.Add("")
            $lines.Add("Coda WordPress:")
            if ($health.jobs) {
                foreach ($property in $health.jobs.PSObject.Properties) {
                    $lines.Add(("  {0}: {1}" -f $property.Name, $property.Value))
                }
            }
            else { $lines.Add("  nessun elemento in coda") }
        }
        catch {
            Set-StatusLabel $siteStatus $false "" "WordPress non raggiungibile"
            $lines.Add("ERRORE WORDPRESS: $($_.Exception.Message)")
        }

        if (-not $ollama.Online) { $lines.Add("ERRORE OLLAMA: usa il pulsante Ripara.") }
        elseif (-not $ollama.Model) { $lines.Add("MODELLO ASSENTE: usa il pulsante Ripara.") }
        $details.Lines = $lines.ToArray()
    }
    catch {
        Set-StatusLabel $agentStatus $false "" "Applicazione non configurata"
        Set-StatusLabel $ollamaStatus $false "" "Ollama non verificato"
        Set-StatusLabel $siteStatus $false "" "WordPress non verificato"
        Set-StatusLabel $modelStatus $false "" "Modello non verificato"
        $details.Text = $_.Exception.Message
    }
    finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
}

$refreshButton.Add_Click({ Refresh-Dashboard })
$restartButton.Add_Click({
    & schtasks.exe /End /TN $TaskName 2>$null | Out-Null
    Start-Sleep -Milliseconds 600
    & schtasks.exe /Run /TN $TaskName | Out-Null
    Start-Sleep -Seconds 1
    Refresh-Dashboard
})
$wordpressButton.Add_Click({
    try {
        $runtime = Get-Runtime
        Start-Process ($runtime.Config.site_url.TrimEnd('/') + "/wp-admin/admin.php?page=calcioaffari-news-engine")
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "CalcioAffari") | Out-Null }
})
$repairButton.Add_Click({
    $repairPath = Join-Path $InstallDir "repair.ps1"
    Start-Process -FilePath (Join-Path $PSHOME "powershell.exe") -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$repairPath`"" -Wait
    Refresh-Dashboard
})
$logButton.Add_Click({
    $logPath = Join-Path $InstallDir "agent.log"
    if (-not (Test-Path $logPath)) { Set-Content $logPath "Nessun evento registrato." -Encoding UTF8 }
    Start-Process notepad.exe -ArgumentList "`"$logPath`""
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 60000
$timer.Add_Tick({ Refresh-Dashboard })
$timer.Start()
$form.Add_Shown({ Refresh-Dashboard })
[void]$form.ShowDialog()
$timer.Stop()
$timer.Dispose()
