# CloudOS — Política de Privacidade e Tratamento de Dados (RC1.1)

O CloudOS foi projetado para oferecer total privacidade ao usuário. Todos os recursos operam localmente na sua máquina, sem envio de telemetria ou rastreamento para servidores externos.

---

## 1. Coleta e Transmissão de Dados: ZERO

- **Zero Telemetria:** O CloudOS não possui código de rastreamento de cliques, tempo de uso, hábitos de navegação ou inventário de arquivos.
- **Zero Analytics Remoto:** Nenhuma informação comportamental é transmitida para terceiros.
- **Sem Conexões Ocultas:** A menos que o usuário abra conscientemente uma página no Navegador integrado (WebView2), o CloudOS não realiza requisições de rede em segundo plano.

---

## 2. Diagnósticos e Logs Sanitizados

Quando o usuário decide gerar um pacote de suporte ou diagnóstico (`scripts/diagnostics/export-diagnostics-bundle.ps1` ou botão "Copiar Diagnóstico Sanitizado" em Configurações):

1. **Caminhos de Usuário:** O caminho absoluto `%USERPROFILE%` (ex: `C:\Users\nome_do_usuario`) é anonimizado para `%USERPROFILE%`.
2. **Nome de Usuário:** O nome da conta local do Windows é substituído por `<USER>`.
3. **Credenciais e Segredos:** Expressões regulares sanitizam automaticamente chaves de API, tokens de autenticação, senhas e credenciais eventualmente registradas em logs de depuração.
4. **Armazenamento Local:** O pacote de diagnóstico em formato `.zip` é gerado apenas no disco local (`%TEMP%`), cabendo unicamente ao usuário inspecionar e decidir se deseja compartilhá-lo.

---

## 3. Armazenamento de Histórico e Área de Transferência

- **Histórico do Menu Iniciar (Recent Apps):** Mantém apenas os últimos 10 aplicativos iniciados, armazenados exclusivamente no arquivo `%LOCALAPPDATA%\CloudOS\preferences-v1.json`.
- **Área de Transferência:** O CloudOS não retém senhas nem dados confidenciais copiados entre aplicativos.
- **Limpeza Fácil:** A qualquer momento, o usuário pode clicar em "Redefinir Configurações" na aba *Sobre* para apagar todo o histórico de personalizações e preferências locais.
