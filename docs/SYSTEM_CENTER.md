# CloudOS System Center

O System Center substitui métricas demonstrativas do antigo Task Manager por dados que a API pública do kernel virtual realmente mantém.

## Processos

Exibe `title/name`, PID, PPID, estado, CPU, memória, prioridade e tempo desde `startTime`. Pesquisa e ordenação usam somente campos do tipo `Process`. O intervalo reservado de PIDs do kernel (`0–99`) é somente leitura no System Center; processos criados pelo shell começam em 100.

Foram removidas métricas sintéticas como `processes.length * 4` para threads, velocidade fixa de CPU e memória "commitada" derivada por multiplicação.

## Desempenho

Amostra uma vez por segundo `kernel.resources`: CPU, RAM usada/total/livre, núcleos, uptime, disco virtual (`usedDisk/totalDisk`) e disponibilidade de rede. CPU e RAM mantêm histórico limitado a 60 amostras.

## Saúde

O resumo usa somente condições observáveis:

- serviço com status `failed`;
- driver `failed` ou `not_found`;
- memória >= 90%;
- CPU >= 95%;
- quantidade de processos suspensos/bloqueados.

## Serviços e drivers

Lista snapshots públicos de `kernel.getAllServices()` e `kernel.getAllDrivers()`. Nesta fase são somente leitura. Não foram adicionados botões falsos de start/stop porque o kernel atual ainda não fornece lifecycle público confiável para isso.

## Compatibilidade

A implementação não acessa `kernel._*`, não altera `App.tsx`, `WindowRenderer` ou a fachada/hardening do kernel e usa os contratos reais de `Process`, `SystemResource`, `ServiceEntry` e `DriverEntry` presentes na base validada.

## Limitações

As métricas pertencem ao kernel virtual CloudOS. GPU, rede por processo, handles e threads reais exigem broker/Host específico em fase posterior.
