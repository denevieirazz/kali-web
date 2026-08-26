# CloudOS como shell principal do computador

## Objetivo

O destino do projeto é fazer o CloudOS ser toda a experiência visível da sessão: desktop, barra de tarefas, menu, configurações, arquivos, terminais e inicialização de aplicativos Windows e Linux. O Windows continua por baixo como kernel, camada de drivers, segurança, Win32, DWM e host do WSL/WSLg.

Isso é um produto válido: uma distribuição/shell própria construída sobre a plataforma Windows. Não é, porém, um kernel independente. Um kernel novo seria outro projeto e perderia a compatibilidade direta com todos os aplicativos e drivers Windows.

## Regra de segurança desta fase

O modo shell permanece **inativo**. A preparação atual não:

- altera `Winlogon`, Registro, boot ou políticas;
- substitui, renomeia ou remove `explorer.exe`;
- habilita Shell Launcher, Custom Logon, Unbranded Boot ou logon automático;
- desabilita UAC, Defender, Windows Update, WinRE ou telas de erro;
- remove AppX, serviços, DWM, Store, WebView2, WSL ou Virtual Machine Platform;
- instala ou remove distribuições WSL.

O script `scripts/test-shell-readiness.ps1` é somente leitura e deixa claro cada requisito ainda bloqueado. `npm run shell:check` é informativo; `npm run shell:gate` retorna erro para CI enquanto houver bloqueios. Uma futura aprovação de assinatura também exige fixar explicitamente o thumbprint do certificado do publicador CloudOS.

## Arquitetura de destino

```text
Winlogon / Shell Launcher v2
            |
            v
CloudOS.Bootstrap (nativo, sem WebView2)
  |-- política de crash-loop
  |-- last-known-good e recuperação
  |-- observa prontidão e saída do shell
  `-- inicia CloudOS.Host
             |
             v
CloudOS.Host / WPF / WebView2
  |-- interface React em tela cheia
  |-- supervisor do agente local
  |-- bridge nativa restrita
  `-- gerenciamento de janelas Windows/WSLg
             |
             v
Agente Node local + Windows + WSL 2 + WSLg
```

O executável registrado futuramente deve permanecer vivo. O Shell Launcher monitora o processo do shell; um atalho que abre outro processo e encerra não é adequado.

## Caminho suportado por edição

- **Enterprise, Education ou IoT Enterprise:** Shell Launcher v2 é o caminho de produção suportado. Ele substitui Explorer por usuário, permite manter Explorer para administradores e define o comportamento quando o shell termina.
- **Windows Pro:** a política `Custom User Interface` pode servir a um piloto por usuário, mas não oferece o mesmo controle de ciclo de vida documentado do Shell Launcher. Não é o destino de produção recomendado.
- **Assigned Access:** atende quiosques restritos, não um desktop híbrido geral, e não deve coexistir com Shell Launcher.
- **Edição direta do valor global `Winlogon\Shell`:** não será adotada pelo CloudOS.

Referências oficiais: [Shell Launcher](https://learn.microsoft.com/en-us/windows/configuration/shell-launcher/), [configuração](https://learn.microsoft.com/en-us/windows/configuration/shell-launcher/configure), [política CustomShell](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-winlogon) e [Assigned Access](https://learn.microsoft.com/en-us/windows/configuration/assigned-access/).

## Portões obrigatórios antes de ativar

1. **Pacote confiável**
   - instalador por máquina em `%ProgramFiles%\CloudOS`;
   - uma única raiz imutável contendo host, bootstrap, Node, agente e build web;
   - host, bootstrap, broker e instalador assinados;
   - catálogo assinado de hashes cobrindo também o agente e o build web;
   - manifesto SHA-256 e atualização A/B atômica;
   - WebView2 e runtime Node presentes e reparáveis.

2. **Recuperação fora da interface web**
   - bootstrap nativo independente de React, Node e WebView2;
   - crash-loop leva ao modo de recuperação, nunca a reinício infinito;
   - last-known-good testado;
   - Explorer preservado;
   - conta administrativa separada usando Explorer;
   - rollback acessível quando o CloudOS não inicia.

3. **Recuperação do Windows**
   - WinRE habilitado;
   - chave BitLocker guardada fora do computador;
   - Proteção do Sistema/ponto de restauração;
   - mídia oficial de recuperação disponível;
   - UAC e desktop seguro preservados.

4. **Confiabilidade**
   - agente morre quando o host morre, sem processo órfão;
   - prontidão só depois do handshake do bundle React, nunca apenas por HTTP 200;
   - health contínuo do host, agente, bridge e React;
   - restart com backoff e limite;
   - logoff, desligamento, lock, suspensão e troca de usuário testados;
   - mutações WSL reconciliadas após UAC/reboot/crash;
   - atualização com rollback após falta de energia.

5. **Qualificação em VM**
   - nunca testar a primeira ativação no computador principal;
   - usar snapshot descartável da mesma edição/build;
   - simular host corrompido, WebView2 ausente, disco cheio, rede offline, backend travado e três crashes seguidos;
   - confirmar entrada na conta administrativa Explorer e rollback.

## Fases

### Fase A — shell preview seguro

CloudOS abre em tela cheia sobre a sessão normal. Explorer continua disponível como fallback. A Central de Prontidão mede capacidades reais e mostra bloqueios. É a fase atual.

### Fase B — candidato instalável

Criar MSI/MSIX ou instalador assinado, bootstrap nativo, atualização A/B, repair e desinstalação. Instalar em `%ProgramFiles%`, mantendo dados do usuário em `%LOCALAPPDATA%`/`%PROGRAMDATA%` conforme sua finalidade.

### Fase C — piloto por usuário em VM

Configurar somente uma conta padrão CloudOS. A conta administrativa continua com `explorer.exe`. Usar inicialmente `DoNothing` quando o shell sair para evitar crash-loop; o bootstrap fornece recuperação. Só depois da matriz de falhas considerar `RestartShell`.

### Fase D — dispositivo dedicado

Depois do piloto, aplicar Shell Launcher v2 numa edição compatível. Custom Logon e Unbranded Boot podem reduzir a marca visual do Windows, mas somente quando recuperação e manutenção já estiverem comprovadas.

### Fase E — redução de componentes

Reduzir a imagem **offline**, com lista allowlisted e testes por componente. Não apagar arquivos/serviços de uma instalação viva. Win32, DWM, GPU, áudio, rede, WebView2, App Installer/Store quando exigidos, virtualização, WSL e WSLg são dependências do objetivo e devem ser preservados.

## Limites permanentes

- UAC/secure desktop e `Ctrl+Alt+Del` são fronteiras do Windows e não devem ser falsificados ou escondidos pelo CloudOS.
- WSLg fornece aplicativos Linux individuais, não um desktop Linux completo dentro do DOM.
- Apps elevados, DRM, anti-cheat, drivers, janelas protegidas e fullscreen exclusivo podem exigir fallback nativo.
- Remover a base do Windows elimina justamente a compatibilidade Win32/WSLg buscada pelo projeto.

Referências: [aplicativos GUI no WSL](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps), [Custom Logon](https://learn.microsoft.com/en-us/windows/configuration/custom-logon/), [Unbranded Boot](https://learn.microsoft.com/en-us/windows/configuration/unbranded-boot/) e [funcionamento do UAC](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/user-account-control/how-it-works).
