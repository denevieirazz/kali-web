# Primeiro acesso e administrador

O CloudOS não possui usuário ou senha padrão.

Na primeira inicialização, a interface chama `GET /api/setup/status`. Quando não há administrador, o assistente solicita nome de exibição, nome de usuário e senha e cria a única conta administradora inicial por `POST /api/setup/admin`. A conta é criada no agente persistente; a interface não cria mais um perfil local separado.

Regras atuais:

- usuário entre 3 e 64 caracteres, começando por letra ou número e usando apenas letras, números, ponto, sublinhado ou hífen;
- nome de exibição com até 80 caracteres; a interface solicita esse campo e o agente usa o usuário como fallback em chamadas compatíveis;
- senha entre 10 e 128 caracteres; frases-senha são aceitas;
- hash bcrypt com custo de produção; a senha não é persistida nem retornada;
- somente um administrador pode vencer a corrida de primeiro acesso;
- um código de recuperação de uso contínuo é mostrado uma única vez e armazenado somente como hash;
- recuperar a conta permite trocar usuário, nome de exibição e senha, preserva a identidade e as operações e invalida sessões anteriores;
- cada recuperação ou rotação invalida o código anterior e mostra um novo código uma única vez;
- tentativas de recuperação são limitadas e o bloqueio sobrevive ao reinício;
- oito logins inválidos dentro de 10 minutos bloqueiam novas tentativas por 5 minutos, sem persistir os dados tentados;
- a redefinição destrutiva da instalação é uma ferramenta de desenvolvimento e fica indisponível no host de produção.

Contas antigas são migradas sem trocar o ID nem o hash da senha. No primeiro login válido, o CloudOS cadastra e mostra o código de recuperação antes de liberar o desktop.

No host nativo, o banco, seu backup e o segredo JWT ficam em `%LOCALAPPDATA%\CloudOS\data`. O arquivo principal é gravado de forma atômica, `cloudos.json.bak` mantém a última cópia válida e a migração v1→v2 preserva uma cópia única `cloudos.json.pre-v2.bak`. Se principal e backup estiverem inválidos, o agente falha fechado em vez de apresentar um primeiro acesso vazio.

Não publique credenciais ou códigos de recuperação. Guarde o código fora do computador; não use a redefinição da instalação como substituto para recuperação de conta.

Depois de cinco códigos incorretos dentro da janela de 15 minutos, novas tentativas de recuperação ficam bloqueadas por 15 minutos. Perder simultaneamente a senha e o código não possui um bypass automático.
