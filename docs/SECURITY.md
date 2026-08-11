# Diretrizes de Segurança — CloudOS-Unified

- **CORS e Origin**: Requisições de WebSocket e HTTP são restritas exclusivamente a `localhost` e `127.0.0.1`.
- **Validação de Tokens**: Tokens JWT não são trafegados via Query String de URL. O WebSocket utiliza handshake ou subprotocolo seguro.
- **Proteção contra Path Traversal**: Caminhos de arquivos no backend e no OPFS são estritamente normalizados.
- **Sem Exposição de Segredos**: Não há chaves de API, senhas ou tokens salvos em repositório. O `.env.example` serve de modelo sem credenciais.
