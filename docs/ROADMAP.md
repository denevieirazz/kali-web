# Roadmap técnico consolidado

## Batch 1 — estabilização de foundation

1. Fonte única de verdade e inventário de branches.
2. Launcher único, pré-requisitos e logs persistentes.
3. Lifecycle visual estável do Terminal sem alterar WSL Core v2/AES-GCM.
4. Capability UX do Browser por modo; candidata WPF permanece separada.
5. Um único CloudOS Files: OPFS + pasta Windows autorizada + Linux Home, com transações e UX visual comum.
6. Storage apresentado com terminologia correta; OPFS não é disco físico.
7. Onboarding responsivo e recuperação local simples; senha min 4 com orientação de força.
8. Validação automatizada + gate físico organizado por SHA/execution-id.

## Após Batch 1

### 1. Runtime seguro para agentes de IA

Capability tokens explícitos, raiz de filesystem, verbos permitidos, validade, aprovação do usuário, journal/audit e revogação. Nenhum agente herda silenciosamente grants do Files.

### 2. Process Manager/System Center

Retomar a branch Linux/cgroups após a base estar estável e repetir gate físico da UI/processos/sinais/cgroups read-only.

### 3. Lifecycle/provisionamento WSL

Unificar diagnóstico, instalação/provisionamento opt-in, estados, reboot e rollback sem misturar com o runtime de arquivos/terminal.

### 4. WSLg e aplicativos Linux

Catálogo, launch, containment/gestão de janela e lifecycle observável.

### 5. Hardware/USB

Inventário primeiro; ações privilegiadas somente por brokers allowlisted e consentimento explícito.

## Fora de escopo atual

- VHDX real: somente design neste lote.
- substituição do Explorer: bloqueada até recovery/watchdog/package trust e validação em VM.
- merge/promoção automática: nunca faz parte do launcher ou da CI.
