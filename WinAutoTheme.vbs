Option Explicit
' Lanca o WinAutoTheme sem abrir janela de console.
Dim fso, shell, dir, ps1, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\WinAutoTheme.ps1"
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ -Apply"
Set shell = CreateObject("WScript.Shell")
shell.Run cmd, 0, False
