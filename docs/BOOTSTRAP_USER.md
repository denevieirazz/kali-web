# Guia de Bootstrap de Usuário — CloudOS-Unified

## 1. Usuário Padrão Pré-Cadastrado
O ambiente em memória inicializa com o usuário administrador padrão:
- **Usuário**: `admin`
- **Senha**: `admin`

---

## 2. Comando de Bootstrap CLI (Documentado)

Para cadastrar novos usuários via script CLI sem auxílio de interface gráfica, utilize o comando abaixo:

```bash
# Executar a partir da pasta CloudOS-Unified/backend
node -e "import('./src/database/index.js').then(({ getDb }) => { const db = getDb(); import('bcryptjs').then(b => { const hash = b.default.hashSync('NOVA_SENHA_AQUI', 10); db.run('INSERT INTO users (id, username, password_hash, role) VALUES (?, ?, ?, ?)', ['user-' + Date.now(), 'NOVO_USUARIO', hash, 'user'], () => console.log('Usuário cadastrado com sucesso!')); }); });"
```

---

## 3. Segurança
- Nenhuma senha plana é armazenada no banco de dados ou enviada nos logs.
- Todos os tokens JWT são assinados via `config.jwtSecret` e transmitidos exclusivamente no cabeçalho `Authorization: Bearer <token>`.
