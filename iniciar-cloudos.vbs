Set WshShell = CreateObject("WScript.Shell")

' Executa o backend em background
WshShell.Run "cmd /c cd /d ""c:\Users\dougl\Music\projeto\cloudos-backend"" && ""C:\Program Files\nodejs\node.exe"" server.js", 0, False

' Executa o frontend em background
WshShell.Run "cmd /c cd /d ""c:\Users\dougl\Music\projeto\cloudos-frontend"" && ""C:\Program Files\nodejs\npm.cmd"" run dev", 0, False

' Aguarda 5 segundos para garantir a inicializacao
WScript.Sleep 5000

' Abre o navegador no endereco do CloudOS
WshShell.Run "http://localhost:5173"


