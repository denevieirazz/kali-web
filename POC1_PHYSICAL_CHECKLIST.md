# POC1_PHYSICAL_CHECKLIST.md

## REGRA DA PROVA

Esta execução não instala nada.

Proibido durante a prova:

```text
apt install
apt-get install
dnf install
pacman
snap install
flatpak install
wsl --install
```

Se um requisito estiver ausente, registrar **BLOQUEADO** e parar naquele gate.

## OBJETIVO

Provar fisicamente:

```text
xclock roda dentro do WSL
        ↓
Xpra transporta a janela
        ↓
Xpra HTML5 aparece dentro da CloudOS Window
        ↓
nenhuma janela Windows externa do xclock
```

## 1. CONFIRMAR A BRANCH

No PowerShell, dentro do repositório:

```powershell
git switch poc/cloudos-linux-runtime-xpra
git status --short
git rev-parse HEAD
```

Esperado:

```text
branch = poc/cloudos-linux-runtime-xpra
working tree sem mudanças locais inesperadas
HEAD = SHA entregue no fechamento desta tarefa
```

Registrar o SHA no relatório físico.

## 2. CONFIRMAR WSL

```powershell
Get-Command wsl.exe
wsl.exe --status
wsl.exe -l -v
```

PASSA se:

- `wsl.exe` existe;
- uma distro aparece;
- a distro pretendida está operacional;
- para o ambiente principal, preferir `kali-linux` se ela já estiver presente.

Se não houver distro:

```text
BLOQUEADO: WSL_DISTRO_MISSING
```

Não instalar uma durante esta prova.

## 3. DEFINIR A DISTRO DA PROVA

Exemplo se já existir `kali-linux`:

```powershell
$distro = 'kali-linux'
```

Se o nome real for outro, usar exatamente o valor mostrado por:

```powershell
wsl.exe -l -q
```

## 4. CONFIRMAR XPRA

```powershell
wsl.exe -d $distro -- sh -lc 'command -v xpra && xpra --version'
```

PASSA se houver caminho e versão.

Se não houver:

```text
BLOQUEADO: XPRA_MISSING
```

Não instalar durante esta prova.

## 5. CONFIRMAR XCLOCK

```powershell
wsl.exe -d $distro -- sh -lc 'command -v xclock'
```

PASSA se retornar um executável.

Se não houver:

```text
BLOQUEADO: LINUX_POC_APP_MISSING
```

Não instalar durante esta prova.

## 6. CONFIRMAR QUE A FAIXA DA POC ESTÁ LIVRE

```powershell
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -ge 14500 -and $_.LocalPort -le 14549 } |
  Sort-Object LocalPort |
  Format-Table LocalAddress,LocalPort,OwningProcess
```

Resultado ideal antes da POC:

```text
nenhum listener 14500-14549
```

Se houver listener, não matar processo desconhecido automaticamente.

Abrir a POC e usar `Limpar órfãos` somente se o próprio CloudOS identificar uma sessão de seu ledger.

## 7. CONFIRMAR AUSÊNCIA DE XPRA ÓRFÃO DA POC

```powershell
wsl.exe -d $distro -- sh -lc 'xpra list 2>/dev/null || true'
```

Observar displays `:100` até `:149`.

Não executar `xpra stop` manualmente em sessão desconhecida.

Se a UI retornar:

```text
LINUX_POC_ORPHANED_SESSION
```

usar o botão `Limpar órfãos`, que só atua sobre sessões conhecidas pelo ledger da POC.

## 8. CAPTURAR BASELINE DE JANELAS WINDOWS

Antes de iniciar xclock:

```powershell
Get-Process |
  Where-Object { $_.MainWindowHandle -ne 0 } |
  Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle |
  Sort-Object ProcessName,Id |
  Export-Csv .\poc1-windows-before.csv -NoTypeInformation -Encoding UTF8
```

Também registrar visualmente:

- desktop Windows;
- Alt+Tab atual.

## 9. INICIAR CLOUDOS PELO FLUXO JÁ EXISTENTE

Usar o mesmo launcher/dev flow normalmente usado para este repositório.

No checkout de desenvolvimento, o comando raiz disponível é:

```powershell
npm run dev
```

Não abrir um navegador externo adicional para o Xpra.

O único local onde o app Linux deve aparecer é a CloudOS Window.

## 10. ABRIR `LINUX RUNTIME POC 1`

No CloudOS:

1. abrir `Linux Runtime POC 1`;
2. não clicar `Abrir XClock` ainda;
3. ler a faixa `READINESS`.

Esperado antes do start:

```text
wsl: OK
distribution: OK
xpra: OK
app: OK
port: OK
orphans: OK
windowsLoopback: PENDENTE
websocket: PENDENTE
```

Se WSL/Xpra/app/porta/órfãos estiverem vermelhos, parar e registrar o código mostrado.

## 11. INICIAR XCLOCK

Selecionar:

```text
XClock
```

Clicar:

```text
Abrir XClock
```

Não executar `xclock` manualmente em outro terminal durante esta etapa.

## 12. OBSERVAR O START

A POC deve atravessar:

```text
readiness
spawn WSL/Xpra
xpra info :display
Windows TCP
Xpra HTTP
Xpra WebSocket
CloudOS capability proxy
iframe
primeira .window remota
```

Se falhar, registrar exatamente `errorCode`.

Códigos mais importantes:

```text
XPRA_SERVER_TIMEOUT
XPRA_WINDOWS_LOOPBACK_BLOCKED
XPRA_HTTP_UNAVAILABLE
XPRA_WEBSOCKET_UNAVAILABLE
XPRA_PROCESS_EXITED
```

## 13. PASSO DECISIVO: CONTAINMENT

PASSA somente se:

```text
xclock está visível dentro da área da CloudOS Window
```

E simultaneamente:

```text
nenhuma janela xclock aparece no desktop Windows
nenhuma nova janela Linux aparece fora do CloudOS
Alt+Tab não mostra um xclock externo
```

Se surgir qualquer janela externa:

```text
FALHOU: CONTAINMENT_BROKEN
```

Não importa se o app funciona.

## 14. CAPTURAR SCREENSHOT PRINCIPAL

Capturar uma imagem onde estejam visíveis:

- desktop/barra CloudOS;
- moldura da CloudOS Window;
- `Linux Runtime POC 1`;
- xclock renderizado dentro do surface;
- rodapé/telemetria da POC.

Nome sugerido:

```text
poc1-xclock-contained.png
```

Esse é o screenshot principal da prova.

## 15. CAPTURAR EVIDÊNCIA DE AUSÊNCIA DE JANELA EXTERNA

Após xclock estar visível:

```powershell
Get-Process |
  Where-Object { $_.MainWindowHandle -ne 0 } |
  Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle |
  Sort-Object ProcessName,Id |
  Export-Csv .\poc1-windows-after.csv -NoTypeInformation -Encoding UTF8
```

Comparar:

```powershell
Compare-Object \
  (Import-Csv .\poc1-windows-before.csv | ForEach-Object { "$($_.ProcessName)|$($_.MainWindowTitle)" }) \
  (Import-Csv .\poc1-windows-after.csv  | ForEach-Object { "$($_.ProcessName)|$($_.MainWindowTitle)" })
```

A comparação é evidência auxiliar.

A evidência obrigatória continua sendo observação visual/Alt+Tab de que nenhum app Linux escapou.

## 16. TESTAR MOUSE

Com xclock:

- mover a CloudOS Window;
- clicar dentro da surface;
- confirmar que o iframe continua ativo.

Para teste mais visível de pointer, iniciar posteriormente `xeyes`.

Resultado:

```text
MOUSE: PASSOU / FALHOU
```

## 17. TESTAR RESIZE

Redimensionar a CloudOS Window em três tamanhos:

```text
pequeno
médio
grande
```

Confirmar:

- iframe permanece contido;
- Xpra não cria janela externa;
- conteúdo continua utilizável;
- health continua saudável.

Resultado:

```text
RESIZE: PASSOU / ALERTA / FALHOU
```

## 18. TESTAR STOP

Clicar:

```text
Stop
```

Esperado:

- surface desaparece;
- sessão some da lista;
- porta deixa de responder;
- display Xpra é encerrado;
- CloudOS continua responsivo.

Verificar Windows:

```powershell
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -ge 14500 -and $_.LocalPort -le 14549 }
```

Verificar WSL:

```powershell
wsl.exe -d $distro -- sh -lc 'xpra list 2>/dev/null || true'
```

## 19. TESTAR RESTART

Iniciar xclock novamente.

Clicar:

```text
Restart
```

Esperado:

```text
sessão antiga encerra
porta/display antigo são liberados
nova sessão inicia
xclock volta dentro da CloudOS Window
restartCount aumenta
```

Resultado:

```text
RESTART: PASSOU / FALHOU
```

## 20. TESTAR XCLOCK + XEYES

Com xclock ativo, selecionar `XEyes` e clicar `Abrir XEyes`.

Esperado:

- duas tabs aparecem no laboratório POC1;
- cada uma possui sessão Xpra própria;
- alternar tabs não abre janela Windows externa;
- xeyes reage ao pointer quando sua tab está ativa.

Resultado:

```text
MULTI_APP_2: PASSOU / FALHOU
```

## 21. TESTAR XTERM

Se `xterm` já estiver instalado:

1. iniciar XTerm;
2. clicar dentro do terminal;
3. digitar texto simples;
4. testar Enter/Backspace/setas;
5. testar copiar/colar texto não sensível.

Registrar:

```text
FOCO:
TECLADO:
CLIPBOARD WINDOWS -> XTERM:
CLIPBOARD XTERM -> WINDOWS/CLOUDOS:
```

Não digitar credenciais durante o teste de clipboard.

## 22. TESTAR GEDIT

Se `gedit` já estiver instalado:

1. iniciar Gedit;
2. digitar texto;
3. testar seleção/copy/paste;
4. abrir um diálogo simples se o app permitir;
5. confirmar que o diálogo permanece dentro do Xpra HTML5/CloudOS Window.

Se gedit não existir:

```text
BLOQUEADO: LINUX_POC_APP_MISSING
```

Não instalar durante a prova.

## 23. TESTAR ESTABILIDADE CURTA

Manter xclock ou xeyes ativo por pelo menos 2 minutos.

Observar:

```text
health
healthFailures
reconnectCount
websocketHandshakeMs
```

Não deve haver:

- loop de reconnect;
- surface branca permanente;
- app externo;
- congelamento CloudOS.

## 24. TESTAR FECHAMENTO DA CLOUDOS WINDOW

Com uma sessão ativa:

1. fechar a CloudOS Window `Linux Runtime POC 1` pela barra do CloudOS;
2. aguardar mais de 1 segundo;
3. verificar portas;
4. verificar `xpra list`.

Esperado:

```text
sessões pertencentes àquela window foram limpas
```

Esse teste valida o owner/lifecycle e o workaround de StrictMode.

## 25. TESTAR RECOVERY DE ÓRFÃO

Somente se for possível provocar sem corromper o ambiente de trabalho:

1. iniciar xclock pela POC;
2. encerrar apenas o backend CloudOS de forma abrupta;
3. manter a distro WSL viva;
4. iniciar novamente o backend;
5. abrir POC1;
6. verificar readiness.

Se a sessão sobreviveu:

```text
LINUX_POC_ORPHANED_SESSION
```

Deve aparecer.

Usar:

```text
Limpar órfãos
```

Depois readiness deve voltar a OK.

Não matar sessões Xpra externas à POC.

## 26. REGISTRAR MÉTRICAS

Para xclock, copiar os valores mostrados pela POC:

```text
BOOT_MS=
WEBSOCKET_HANDSHAKE_MS=
HEALTH_MS=
IFRAME_LOAD_MS=
FIRST_REMOTE_WINDOW_MS=
RESTART_COUNT=
RECONNECT_COUNT=
HEALTH_FAILURES=
```

Usar `POC1_METRICS.md` como contrato.

## 27. CAPTURAR SCREENSHOTS ADICIONAIS

Se os testes forem executados:

```text
poc1-xeyes-contained.png
poc1-xterm-contained.png
poc1-gedit-contained.png
poc1-multi-app.png
poc1-readiness-ok.png
```

Não usar screenshot de estado mockado como prova de containment.

## 28. RESULTADO FINAL

### VIÁVEL

Somente se, no mínimo:

```text
xclock real executou no WSL
Xpra real ficou healthy
WebSocket real abriu
xclock apareceu dentro da CloudOS Window
mouse/resize básicos funcionaram
Stop limpou a sessão
janela Windows externa do app = 0
```

### NÃO VIÁVEL

Se um requisito funcional da cadeia falhar na máquina preparada, registrar o boundary exato.

### BLOQUEADO

Se WSL/distro/Xpra/xclock não estiverem previamente presentes, registrar BLOQUEADO em vez de atribuir falha à arquitetura.

## ARQUIVOS DE EVIDÊNCIA DA EXECUÇÃO

Guardar juntos:

```text
SHA.txt
poc1-windows-before.csv
poc1-windows-after.csv
poc1-xclock-contained.png
screenshots adicionais
métricas copiadas da UI
diag/errorCode se houver falha
```

Nenhuma evidência deve ser fabricada quando um gate anterior estiver bloqueado.
