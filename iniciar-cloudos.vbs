Set WshShell = CreateObject("WScript.Shell")

' Executa o backend em segundo plano (0 = oculta a janela)
WshShell.Run "cmd /c ""set PATH=C:\Program Files\nodejs;%PATH% && cd /d c:\Users\dougl\Music\projeto\cloudos-backend && node server.js""", 0, False

' Executa o frontend em segundo plano (0 = oculta a janela)
WshShell.Run "cmd /c ""set PATH=C:\Program Files\nodejs;%PATH% && cd /d c:\Users\dougl\Music\projeto\cloudos-frontend && npm run dev""", 0, False

' Aguarda 4 segundos para os servidores iniciarem
WScript.Sleep 4000

' Abre a interface web no navegador padrão
WshShell.Run "http://localhost:5173"
