[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallDir)

$ErrorActionPreference = 'Stop'
$resolvedInstall = [IO.Path]::GetFullPath($InstallDir)
if (-not (Test-Path -LiteralPath $resolvedInstall)) {
    # A clean installation has no runtime to stop and Setup creates the app
    # directory only after PrepareToInstall returns successfully.
    exit 0
}
$agentPaths = @([IO.Path]::GetFullPath((Join-Path $resolvedInstall 'agent.ps1'))) + @(
    Get-ChildItem -LiteralPath $resolvedInstall -Filter 'agent-*.ps1' -File -ErrorAction SilentlyContinue | ForEach-Object FullName
)
$logPath = Join-Path $resolvedInstall 'upgrade.log'
function Write-PreinstallLog([string]$Level, [string]$Message) {
    Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ("{0:o} [{1}] Preinstall: {2}" -f (Get-Date), $Level, $Message)
}
if (-not ('CalcioAffari.LockingProcesses' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace CalcioAffari {
  public static class LockingProcesses {
    const int ERROR_MORE_DATA = 234;
    const int CCH_RM_SESSION_KEY = 32;
    const int CCH_RM_MAX_APP_NAME = 255;
    const int CCH_RM_MAX_SVC_NAME = 63;

    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS {
      public int dwProcessId;
      public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct RM_PROCESS_INFO {
      public RM_UNIQUE_PROCESS Process;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)] public string strAppName;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)] public string strServiceShortName;
      public uint ApplicationType;
      public uint AppStatus;
      public uint TSSessionId;
      [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint handle, int flags, StringBuilder key);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint handle, uint files, string[] fileNames, uint apps, IntPtr appList, uint services, string[] serviceNames);
    [DllImport("rstrtmgr.dll")]
    static extern int RmGetList(uint handle, out uint needed, ref uint count, [In, Out] RM_PROCESS_INFO[] affected, ref uint rebootReasons);
    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint handle);

    public static int[] Get(string path) {
      uint handle;
      var key = new StringBuilder(CCH_RM_SESSION_KEY + 1);
      if (RmStartSession(out handle, 0, key) != 0) return new int[0];
      try {
        if (RmRegisterResources(handle, 1, new[] { path }, 0, IntPtr.Zero, 0, null) != 0) return new int[0];
        uint needed = 0, count = 0, reasons = 0;
        int result = RmGetList(handle, out needed, ref count, null, ref reasons);
        if (result != ERROR_MORE_DATA || needed == 0) return new int[0];
        var info = new RM_PROCESS_INFO[needed];
        count = needed;
        if (RmGetList(handle, out needed, ref count, info, ref reasons) != 0) return new int[0];
        var ids = new List<int>();
        for (int index = 0; index < count; index++) ids.Add(info[index].Process.dwProcessId);
        return ids.ToArray();
      } finally { RmEndSession(handle); }
    }
  }
}
'@
}
try {
    $strictPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    foreach ($task in @('CalcioAffari Local Agent', 'CalcioAffari Local Agent Watchdog')) {
        & schtasks.exe /End /TN $task 2>$null | Out-Null
    }
    $ErrorActionPreference = $strictPreference
    $locking = @($agentPaths | ForEach-Object { [CalcioAffari.LockingProcesses]::Get($_) } | Sort-Object -Unique)
    foreach ($processId in $locking) {
        if ($processId -ne $PID) {
            Stop-Process -Id ([int] $processId) -Force -ErrorAction SilentlyContinue
        }
    }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $running = @($agentPaths | ForEach-Object { [CalcioAffari.LockingProcesses]::Get($_) } | Sort-Object -Unique)
        if (-not $running) {
            Write-PreinstallLog 'INFO' 'Agente precedente arrestato.'
            exit 0
        }
        Start-Sleep -Milliseconds 250
    }
    Write-PreinstallLog 'ERROR' ('Processo agente ancora attivo: ' + (($running | ForEach-Object {[string] $_}) -join ','))
}
catch {
    Write-PreinstallLog 'ERROR' $_.Exception.Message
}
exit 1
