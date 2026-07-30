Set WshShell = CreateObject("WScript.Shell")

' Executa o backend usando o caminho completo do Node.exe (sem janela)
WshShell.Run "cmd /c ""cd /d c:\Users\dougl\Music\projeto\cloudos-backend && ""C:\Program Files\nodejs\node.exe"" server.js""", 0, False

' Executa o frontend usando o caminho completo do npm.cmd (sem janela)
WshShell.Run "cmd /c ""cd /d c:\Users\dougl\Music\projeto\cloudos-frontend && ""C:\Program Files\nodejs\npm.cmd"" run dev""", 0, False

' Aguarda 4 segundos para os servidores subirem
WScript.Sleep 4000

' Abre o navegador no endereço do CloudOS
WshShell.Run "http://localhost:5173"

