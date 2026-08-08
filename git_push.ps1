$gitExe = "C:\Users\dougl\AppData\Local\Programs\MinGit\cmd\git.exe"

Write-Host "Adicionando arquivos modificados e novos..."
& $gitExe add -A

Write-Host "`nStatus do repositório:"
& $gitExe status --short

Write-Host "`nCriando commit com as implementações das Tarefas 01 a 06..."
& $gitExe commit -m "feat(security): implement multi-user isolation, scope guard engine, hardened wsl installer and context-aware scanner integration"

Write-Host "`nEnviando commits para o GitHub (https://github.com/denevieirazz/kali-web)..."
& $gitExe push origin main
