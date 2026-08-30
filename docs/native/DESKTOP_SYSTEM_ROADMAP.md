# CloudOS Desktop System sobre Windows — plano de entrega

## Estado desta entrega

Base `work/files-storage-v5` / `c04745a8c9ffea33f8ef829f7b6ac86fc7272c33`,
com alterações locais identificadas pelo fingerprint do manifesto. Não é um novo
kernel e ainda não é uma distribuição pronta para substituir Explorer em produção.

Implementado nesta etapa:

- Correção do falso positivo `oledb32.lib`, mantendo a rejeição da dependência no código; nove casos de regressão.
- Correção do ciclo de eventos causado por SetWindowRgn no dock; fixture Win32 exercita fila de eventos, resize, regiões e recursos GDI. A versão original entra em loop.
- Remoção de repinturas completas redundantes do desktop provocadas por eventos de janelas externas; atualizações periódicas e mudanças do desktop continuam ativas. O orçamento de CPU ainda depende de perfil e medição.
- `CloudOS.Recovery.exe` independente de CloudOS.exe, runtime e WebView2; ações explícitas, confirmação antes de encerramento forçado, validação por caminho/usuário/sessão no mesmo handle.
- Watchdog oferece Recovery ao esgotar reinícios; mantém mensagem de erro caso não consiga iniciar o Recovery. Não há fallback automático habilitado.
- Revalidação após resume na fila da UI, nova tentativa de registro WTS a cada 30 ticks quando o serviço ainda não está pronto, preservação do checkpoint após inicialização incompleta e tratamento de erro GetMessage.
- Coletor de diagnóstico local com lista explícita de campos, tolerância a manifesto corrompido, proteção de evidências e amostragem de CPU/RAM/threads. Não coleta documentos, títulos, histórico, credenciais, comandos ou dumps; não envia dados.
- Recovery incluído no build, fingerprint, manifesto, verificador, ZIP portátil e CI. Manifesto distingue fontes localmente modificadas com `source_tree_dirty`.
- Correção da autorreferência do fingerprint: a pasta de artefatos gerados não entra no hash de fontes. Teste cobre empacotamento sem invalidação e alteração de fonte do Recovery com invalidação.

## Etapas e critérios de aceite

| Frente do pedido | Próxima entrega verificável | Critério antes de considerar concluído |
|---|---|---|
| 1. Estabilidade | Soak automatizado e instrumentação de readiness/hang | 24 h por configuração sem crash/hang; filas e recursos limitados; depois semanas de uso piloto |
| 2. Lifecycle | Matriz suspend/resume, WTS, RDP e hotplug | Checkpoints íntegros e exatamente uma instância após cada transição; logoff/restart somente em VM de teste |
| 3. Substituição Explorer | Supervisor externo com timeout de readiness e retorno seguro | Teste de boot/crash/update em VM; Explorer recuperável sem CloudOS; Shell Launcher permanece opt-in |
| 4. Files | Testes reais de namespace, operações e extensões Shell | Cópia cancelável grande, conflito, UAC, reparse, WSL/rede, recycle e submenus sem bloquear UI |
| 5. Start/Search | Índice unificado e cancelamento de consultas antigas | Digitação rápida sem bloqueio com milhares de itens e SystemIndex desligado/lento |
| 6. Taskbar/Dock | Multi-monitor/DPI/fullscreen, jump lists e badges | Maximização respeita rcWork; cinco ciclos por monitor; nenhuma área invisível intercepta input |
| 7. Hardware | Fluxos nativos de áudio, GSMTC, Wi-Fi e Bluetooth | Mixer independente entre dois apps, credenciais nunca em logs, reconexão/ausência de hardware tratadas |
| 8. Settings | Inventário e navegação unificada das preferências | Uma fonte de verdade por configuração; persistência e feedback de erro; links ao Windows claramente identificados |
| 9. Instalação/update | Instalador nativo e staging A/B por usuário | Atualização interrompida não perde versão boa; rollback offline; Stable/Beta/Dev e desinstalação testados |
| 10. Segurança | Revisão de IPC, permissões, assinatura e cadeia de release | Authenticode com identidade real, sem certificado fictício; revisão de ameaças; nenhuma elevação silenciosa |
| 11. Apps | Identidade e protocolo de ativação/lifecycle comuns | Abrir/focar/restaurar/grupar previsíveis; apps internos não duplicados após recovery |
| 12. Multiusuário | Testes com duas contas e duas sessões | Estado e IPC separados; ações de recovery não alcançam outra conta/sessão/instalação |
| 13. Acessibilidade | UIA para superfícies customizadas e teclado integral | Narrator, contraste, IME, foco, touch e escala 100–300% validados; automação consegue selecionar as superfícies |
| 14. Performance | Perfil de repaints, cache e timers | Orçamento de idle definido e medido; CPU abaixo de 1% como meta inicial, memória sem crescimento sustentado |
| 15. Composição | Protótipo DirectComposition isolado | Frame pacing medido e fallback funcional; sem migrar tudo antes de medir |
| 16. Widgets | Modelo persistente de posição/tamanho/visibilidade | Layout sobrevive a DPI/monitores/restart; serviços opcionais e canceláveis |
| 17. Visual | Inventário de componentes e estados | Mesmos tokens/estados de foco, erro, loading e acessibilidade em todas as superfícies |
| 18. Qualidade | Matriz CI e bundles de diagnóstico | Testes unitários/comportamento/UI; artifacts de falha sanitizados; dump de memória só com consentimento separado |
| 19. Recovery | Expandir utilitário independente para safe mode/repair/rollback | Não apaga estado sem backup; funciona com shell quebrado; ações destrutivas exigem confirmação |
| 20. Release | Checklist versionado e changelog de compatibilidade | Toda release registra base, fingerprint, assinatura, testes, riscos, recuperação e limitações |

Ordem: estabilizar e medir → recuperação e sessão → integração de Files/Start/dock
→ hardware/settings/acessibilidade → instalador/update/assinatura → piloto controlado
→ substituição opt-in do shell. Acabamento visual avança sem enfraquecer esses critérios.

## Operação atual

Compilar pelo entrypoint habitual `scripts\native\build-cloudos-native.cmd Release`.
Abrir pelo launcher `Iniciar CloudOS Nativo.cmd`, que continua validando proveniência.
Para recuperação manual, abrir `desktop\CloudOS.NativeShell\bin\Release\CloudOS.Recovery.exe`.
Fechar a janela de Recovery não altera nada. Encerrar CloudOS à força pode perder
edições não salvas de apps internos; o aviso pede confirmação. Explorer é iniciado
por ação explícita e caminho do diretório Windows. O utilitário não altera Winlogon,
Shell Launcher, ACLs, contas nem políticas do Windows.

Diagnóstico: `pwsh -File scripts\native\collect-native-diagnostics.ps1 -SampleSeconds 300`.
Saída padrão: `%LOCALAPPDATA%\CloudOS\Diagnostics\native-<data>-<id>.json`.
No ZIP, o mesmo script opera a partir do diretório do pacote. A assinatura ainda
pode aparecer como `NotSigned`: SHA256 garante integridade contra o manifesto,
não identidade do editor nem autenticidade de um manifesto substituído.

## Limites desta etapa

Não há promessa de estabilidade absoluta, fallback de boot validado, safe mode,
rollback/instalador comercial, assinatura de produção, UIA completo, suporte a todo
hardware ou soak de dias. Recovery de boot e encerramento real de processos de outras
instalações/sessões precisam de ambiente isolado. Não ativar o shell padrão até passar
a matriz de qualidade. A validação de processo/caminho é uma barreira de escopo,
não uma sandbox contra código malicioso executando como o próprio usuário.
