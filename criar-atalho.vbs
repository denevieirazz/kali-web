' =====================================================================
' 🛡️ CloudOS Setup - Criador de Atalho na Área de Trabalho
' =====================================================================

On Error Resume Next

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")

strDesktop = objShell.SpecialFolders("Desktop")
strPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
If Right(strPath, 1) <> "\" Then strPath = strPath & "\"

strTarget = strPath & "setup_cloudos.vbs"

Set objShortcut = objShell.CreateShortcut(strDesktop & "\Instalar CloudOS.lnk")
objShortcut.TargetPath = strTarget
objShortcut.WorkingDirectory = strPath
objShortcut.IconLocation = "%SystemRoot%\System32\shell32.dll,21"
objShortcut.Description = "Instalador Web do CloudOS"
objShortcut.Save

MsgBox "Atalho 'Instalar CloudOS' criado com sucesso na sua Area de Trabalho!" & vbCrLf & vbCrLf & _
       "Dê um duplo clique nele para iniciar o assistente visual de instalacao.", _
       64, "CloudOS - Instalador"
