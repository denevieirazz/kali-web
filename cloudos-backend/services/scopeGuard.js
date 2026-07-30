// Valida se o target do usuário está dentro dos escopos autorizados do projeto
function validateTargetAgainstScope(target, scopes) {
  if (!target || typeof target !== 'string') return { allowed: false, reason: 'Target inválido.' };

  for (const scope of scopes) {
    if (scope.type === 'wildcard' && target.endsWith(scope.target.replace('*', ''))) {
      return { allowed: true };
    }
    if (scope.type === 'domain' && target === scope.target) {
      return { allowed: true };
    }
    if (scope.type === 'ip' && target === scope.target) {
      return { allowed: true };
    }
    if (scope.type === 'cidr') {
      try {
        // Validação simples de sub-rede se ipaddr-js não estiver instalado
        if (target.startsWith(scope.target.split('/')[0].split('.').slice(0, 3).join('.'))) {
          return { allowed: true };
        }
      } catch (e) {
        // Ignora erros de sintaxe
      }
    }
  }
  return { allowed: false, reason: `Target ${target} não está autorizado no escopo do projeto.` };
}

module.exports = { validateTargetAgainstScope };
