Option Explicit

Dim arguments, fileSystem, shell, targetPath, versionedTarget, powershellPath, commandLine

Set arguments = WScript.Arguments
If arguments.Count <> 1 Then
    WScript.Quit 2
End If

Set fileSystem = CreateObject("Scripting.FileSystemObject")
targetPath = fileSystem.GetAbsolutePathName(arguments.Item(0))
If Not fileSystem.FileExists(targetPath) Then
    WScript.Quit 3
End If
If LCase(fileSystem.GetExtensionName(targetPath)) <> "ps1" Then
    WScript.Quit 4
End If

' Existing 1.1.2 scheduled tasks can keep their stable agent.ps1 argument.
' The launcher atomically redirects that legacy entry point to this release.
If LCase(fileSystem.GetFileName(targetPath)) = "agent.ps1" Then
    versionedTarget = fileSystem.BuildPath(fileSystem.GetParentFolderName(targetPath), "agent-1.2.4.ps1")
    If fileSystem.FileExists(versionedTarget) Then
        targetPath = versionedTarget
    End If
End If

Set shell = CreateObject("WScript.Shell")
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
If Not fileSystem.FileExists(powershellPath) Then
    WScript.Quit 5
End If

shell.CurrentDirectory = fileSystem.GetParentFolderName(targetPath)
commandLine = Chr(34) & powershellPath & Chr(34) & _
    " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & _
    Chr(34) & targetPath & Chr(34)

' WScript.exe is a GUI-subsystem process. Window style 0 prevents Windows from
' creating a console before PowerShell can apply -WindowStyle Hidden.
shell.Run commandLine, 0, False
