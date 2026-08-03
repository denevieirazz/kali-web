Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

serverScript = scriptDir & "\server_cloudos.ps1"
portFile = scriptDir & "\cloudos_active_port.txt"

' Limpar arquivo de porta anterior se existir
If fso.FileExists(portFile) Then
    On Error Resume Next
    fso.DeleteFile portFile, True
    On Error GoTo 0
End If

' Inicia o servidor Web Desktop do CloudOS em segundo plano OCULTO (windowStyle = 0)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & serverScript & Chr(34)
WshShell.Run cmd, 0, False

' Aguardar ate o servidor criar o arquivo cloudos_active_port.txt (max 8 segundos)
Dim port
port = "5173"
Dim waitCount
waitCount = 0
Do While waitCount < 16
    WScript.Sleep 500
    waitCount = waitCount + 1
    If fso.FileExists(portFile) Then
        On Error Resume Next
        Dim f
        Set f = fso.OpenTextFile(portFile, 1)
        If Not f.AtEndOfStream Then
            port = Trim(f.ReadLine())
        End If
        f.Close
        On Error GoTo 0
        If port <> "" Then Exit Do
    End If
Loop

' Abre a interface do CloudOS no navegador padrao via Shell.Application (evita erro 80070002)
Set objShell = CreateObject("Shell.Application")
objShell.Open "http://localhost:" & port
