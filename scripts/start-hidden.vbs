Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Obtem o diretorio do script
ScriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
RootDir = fso.GetParentFolderName(ScriptDir)
PsScript = Chr(34) & ScriptDir & "\start-dev.ps1" & Chr(34)

' Executa o PowerShell de forma 100% invisivel (janela oculta = 0)
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -File " & PsScript, 0, False
