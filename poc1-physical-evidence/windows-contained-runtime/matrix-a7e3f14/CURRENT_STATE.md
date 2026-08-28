# PR #16 — validação física do runtime Win32

## Candidato exato do produto

- Repositório: `denevieirazz/kali-web`
- PR: `#16`
- Branch do produto: `fix/cloudos-runtime-launch-rebind`
- Base validada: `12c4dd613aa7d700a0a558286e0f1446df51c0dd`
- SHA exato a validar fisicamente: `a7e3f14996113cafec7edc25a165db521e34c53c`
- Branch de evidência: `evidence/pr16-physical-a7e3f14`

A branch de evidência foi criada diretamente do SHA acima. Este arquivo e futuras evidências podem avançar a branch de evidência; isso **não altera** o SHA do produto que deve ser executado/testado.

## Gates automatizados do SHA exato

- CloudOS CI Baseline run `33203437072`: **SUCCESS**
- Windows Installer Capability CI run `33203437071`: **SUCCESS**

No CloudOS CI passaram, entre outros:

- lint;
- frontend build;
- backend + integration;
- E2E;
- frontend unit;
- CloudOS.Host build + Host Tests;
- Browser response/freshness contracts;
- Bootstrap build/tests;
- baseline Playwright;
- Browser opening lifecycle;
- native Browser WebView2 tests.

Passos condicionais marcados como `skipped` não representam falha.

## O que este candidato corrige genericamente

Este candidato não contém adapter de containment por Brave, Bionic, Telegram ou outro aplicativo específico. Esses programas servem apenas como representantes físicos de classes de comportamento.

O runtime agora cobre, de forma genérica dentro da fronteira Win32/Job/capture atual:

- shortcut com argv real sem violar o contrato de launch kind;
- launcher/root process -> GUI descendente no mesmo Job;
- splash/bootstrap HWND -> HWND final, inclusive com PID descendente diferente;
- substituição do source durante attach e durante layout;
- correlação por `launchProcessId` estável do Job, mantendo o PID físico do HWND separado;
- rebind somente quando existe exatamente um candidato quarantined do mesmo Job;
- grace de 8 s para transições de janela;
- serialização das operações de capture/attach para evitar corrida WGC;
- bloqueio fail-closed de handoff/singleton para instância externa do mesmo executável quando não há namespace explícito por launch;
- isolamento por launch para Chromium-family/Firefox com profile CloudOS próprio e aleatório;
- probe de instância externa com timeout bounded de 8 s, ainda fail-closed, para não confundir jitter de startup do PowerShell no runner Windows com falha lógica.

## Matriz física obrigatória

Executar a prova física no Windows usando **exatamente** o SHA do produto acima.

1. **Win32 simples** — abrir, capturar, focar, redimensionar, minimizar/restaurar e fechar sem desktop/Alt+Tab leak.
2. **Splash/bootstrap -> janela final** — a janela CloudOS deve sobreviver à destruição do splash e rebindar à janela final do mesmo launch Job.
3. **Launcher -> child GUI** — a GUI descendente deve permanecer atribuída ao mesmo Job e ser capturada.
4. **Electron/Chromium** — validar transição de bootstrap e permanência do capture; o nome do aplicativo não deve ser usado como critério de containment.
5. **Shortcut/script -> GUI** — preservar argv/working directory seguros e manter a GUI dentro da fronteira suportada.
6. **Instância externa preexistente do mesmo executável** — para launch direto não isolado, deve falhar fechado antes de permitir handoff/cross-Job.
7. **Close/reopen** — após fechar o launch anterior, um novo launch deve conseguir prosseguir sem herdar sessão/Job antigo.
8. **Duas instâncias Chromium/Firefox isoladas** — profiles por launch distintos; nenhuma adoção da instância externa normal do usuário.
9. **Multiwindow ambíguo** — se mais de uma superfície principal igualmente plausível permanecer, caracterizar como limite/fail-closed; não escolher arbitrariamente a primeira.
10. **Brokered/elevated/protected boundary** — confirmar fail-closed quando a GUI sai da fronteira de Job/capture suportada.

## Critério de aprovação física

Para cada caso suportado, registrar pelo menos:

- launch/root PID;
- PIDs membros do Job;
- HWND/PID antigo e novo quando houver replacement;
- `launchProcessId` das sessões públicas;
- containment mode/state;
- ausência de janela real exposta no desktop/Alt+Tab enquanto capturada;
- resultado de close/teardown;
- logs Host/WGC e screenshot/evidência quando aplicável.

A aprovação exige que uma transição suportada permaneça dentro do mesmo launch Job e que não haja adoção silenciosa de processo externo.

## Limites intencionais desta fase

Não declarar suporte universal para todos os programas do Windows. Permanecem fora ou fail-closed quando não podem ser atribuídos com segurança ao launch atual:

- UWP/MSIX/brokered fora do Job;
- elevado/protegido/secure desktop;
- singleton que delega para processo externo e não oferece namespace isolado por launch;
- multiwindow que requer múltiplas superfícies públicas simultâneas e não possui um único candidato principal inequívoco.

## Estado

Automação do candidato exato: **GREEN**.

Validação física do candidato exato: **PENDENTE**.

PR deve permanecer **DRAFT** e não deve ser mergeado até esta matriz física ser concluída.
