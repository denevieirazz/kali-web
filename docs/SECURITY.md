# Diretrizes de Segurança — CloudOS Unified

A política canônica, o modelo de confiança e os limites conhecidos estão em [`../SECURITY.md`](../SECURITY.md).

No host nativo, a origem do documento aceita pelo agente é exatamente `http://cloudos.localhost`; a API e o WebSocket continuam em `127.0.0.1` numa porta efêmera. Origens de Vite/localhost só são aceitas quando configuradas para desenvolvimento. Tokens não são enviados em query string, credenciais e códigos de recuperação não pertencem ao repositório e caminhos expostos pelo agente devem ser normalizados e limitados a raízes concedidas.
