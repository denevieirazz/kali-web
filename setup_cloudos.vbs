' =====================================================================
' 🛡️ CloudOS Setup - Lançador Silencioso (Sintaxe VBScript Corrigida)
' Resolvido erro 800A0400 utilizando Chr(34) para aspas duplas
' =====================================================================

On Error Resume Next

Set objShell = CreateObject("Shell.Application")
Set objFSO = CreateObject("Scripting.FileSystemObject")

' Pegar caminho do script
strPath = objFSO.GetParentFolderName(WScript.ScriptFullName)
If Right(strPath, 1) <> "\" Then strPath = strPath & "\"

strInstallerPath = strPath & "installer\server_installer.ps1"

' Verificar se existe
If Not objFSO.FileExists(strInstallerPath) Then
    MsgBox "Arquivo server_installer.ps1 não encontrado!" & vbCrLf & vbCrLf & _
           "Caminho esperado:" & vbCrLf & strInstallerPath, _
           16, "CloudOS - Erro"
    WScript.Quit 1
End If

' Executar PowerShell com elevação UAC usando Chr(34) para evitar erro 800A0400
strArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & strInstallerPath & Chr(34)
objShell.ShellExecute "powershell.exe", strArgs, strPath, "runas", 0

' Aguardar 3 segundos para o servidor iniciar
WScript.Sleep 3000

' Tentar abrir o navegador lendo a porta ativa
Dim attempts
attempts = 0
strPortFile = strPath & "installer\active_port.txt"

Do While attempts < 10
    If objFSO.FileExists(strPortFile) Then
        Set objFile = objFSO.OpenTextFile(strPortFile, 1)
        strPort = Trim(objFile.ReadAll)
        objFile.Close
        
        If strPort <> "" Then
            strURL = "http://localhost:" & strPort
            objShell.ShellExecute strURL, "", "", "open", 1
            Exit Do
        End If
    End If
    
    WScript.Sleep 1000
    attempts = attempts + 1
Loop

' Se não conseguiu abrir, mostrar mensagem
If attempts >= 10 Then
    MsgBox "O instalador está rodando em segundo plano." & vbCrLf & vbCrLf & _
           "Abra manualmente no navegador:" & vbCrLf & _
           "http://localhost:9999", _
           64, "CloudOS Installer"
End If

WScript.Quit 0
