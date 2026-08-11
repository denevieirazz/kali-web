# Política de Segurança — CloudOS Unified

## 🛡️ Versões Suportadas

Apenas a versão mais recente da branch principal recebe correções ativas de segurança.

| Versão | Suportada |
| --- | --- |
| 1.0.x (Web) | :white_check_mark: |
| < 1.0 | :x: |

---

## 🔒 Reportando uma Vulnerabilidade

Agradecemos o relato responsável de possíveis vulnerabilidades de segurança.

**Instruções para Notificação:**
1. **Não abra uma Issue pública** descrevendo a vulnerabilidade ou contendo dados sensíveis, tokens ou credenciais.
2. Envie um e-mail com os detalhes técnicos e passos de reprodução para:
   `denevieirazz@gmail.com`
3. Inclua:
   - Descrição detalhada da vulnerabilidade
   - Componente afetado (Frontend, Backend, Terminal WSL, OPFS, etc.)
   - Passos para reprodução com prova de conceito (PoC) não-destrutiva
   - Impacto estimado

Responderemos em até 48 horas úteis com a confirmação de recebimento e o plano de mitigação.

---

## 🔐 Práticas de Segurança Implementadas

- **Isolamento de Origem**: Bind exclusivamente em `127.0.0.1` e validação estrita de CORS.
- **Autenticação**: Hash bcrypt para credenciais de acesso e assinatura de tokens JWT criptograficamente seguros gerados aleatoriamente.
- **Execução Segura**: Chamadas de subprocessos utilizam spawn em array (`execFileSync`), prevenindo injeções de comando via shell.
- **Proteção de Dados**: Armazenamento de arquivos no cliente via Origin Private File System (OPFS) isolado na origem do navegador.
