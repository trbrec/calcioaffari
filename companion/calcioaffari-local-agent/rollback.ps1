[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$TargetVersion,
    [string]$InstallDir = ''
)

$ErrorActionPreference = 'Stop'
if (-not $InstallDir) {
    $InstallDir = if ($env:CA_QUALIFICATION_MODE -eq '1' -and [string]$env:CA_INSTALL_DIR_OVERRIDE -match '^[A-Za-z]:\\') {
        [string]$env:CA_INSTALL_DIR_OVERRIDE
    } else { Join-Path $env:LOCALAPPDATA 'CalcioAffari' }
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
if (-not (Test-Path -LiteralPath $InstallDir)) { throw 'Installazione CalcioAffari non trovata.' }
. (Join-Path $InstallDir 'common.ps1')

$targetAgent = Join-Path $InstallDir ("agent-{0}.ps1" -f $TargetVersion)
if (-not (Test-Path -LiteralPath $targetAgent)) {
    throw "Runtime di rollback agent-$TargetVersion.ps1 non trovato. Installare prima il pacchetto precedente."
}

Stop-CalcioAffariScheduledTask -Name 'CalcioAffari Local Agent' | Out-Null
Stop-CalcioAffariScheduledTask -Name 'CalcioAffari Local Agent Watchdog' | Out-Null
$archive = Join-Path $InstallDir ('rollback-disabled\' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
$moved = @()
foreach ($file in Get-ChildItem -LiteralPath $InstallDir -File -ErrorAction Stop) {
    if ($file.Name -notmatch '^(?:agent|version)-(\d+\.\d+\.\d+)\.(?:ps1|json)$') { continue }
    if ([version]$Matches[1] -le [version]$TargetVersion) { continue }
    if (-not $file.FullName.StartsWith($InstallDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Percorso runtime non sicuro durante il rollback.'
    }
    New-Item -ItemType Directory -Force -Path $archive | Out-Null
    Move-Item -LiteralPath $file.FullName -Destination (Join-Path $archive $file.Name)
    $moved += $file.Name
}

$resolved = $targetAgent
if ([IO.Path]::GetFileName($resolved) -ne ("agent-{0}.ps1" -f $TargetVersion)) {
    throw "Il runtime $TargetVersion non è disponibile dopo il rollback."
}
$upgrade = Join-Path $InstallDir 'upgrade.ps1'
if (Test-Path -LiteralPath $upgrade) { & $upgrade }
if ($LASTEXITCODE -ne 0) { throw "Riavvio del runtime $TargetVersion fallito." }

[pscustomobject]@{
    target_version = $TargetVersion
    active_agent = [IO.Path]::GetFileName($resolved)
    newer_files_archived = @($moved)
    data_preserved = $true
} | ConvertTo-Json -Depth 5
