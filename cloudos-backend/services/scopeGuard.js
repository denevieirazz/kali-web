// Valida se o target do usuário está dentro dos escopos autorizados do projeto
function ipToLong(ip) {
  return ip.split('.').reduce((acc, octet) => ((acc << 8) + parseInt(octet, 10)) >>> 0, 0);
}

function isIpInCidr(ip, cidr) {
  const [range, bits = 32] = cidr.split('/');
  const mask = ~(2 ** (32 - parseInt(bits, 10)) - 1) >>> 0;
  const ipLong = ipToLong(ip);
  const rangeLong = ipToLong(range);
  return (ipLong & mask) === (rangeLong & mask);
}

function validateTargetAgainstScope(target, scopes) {
  if (!target || typeof target !== 'string') return { allowed: false, reason: 'Target inválido.' };
  if (!scopes || !Array.isArray(scopes) || scopes.length === 0) {
    return { allowed: false, reason: 'Nenhum escopo autorizado configurado para o projeto.' };
  }

  const cleanTarget = target.trim().toLowerCase();

  for (const scope of scopes) {
    if (!scope || !scope.target) continue;
    const scopeTarget = scope.target.trim().toLowerCase();

    if (scope.type === 'wildcard') {
      const baseDomain = scopeTarget.replace(/^\*\.?/, '');
      if (cleanTarget === baseDomain || cleanTarget.endsWith('.' + baseDomain)) {
        return { allowed: true };
      }
    } else if (scope.type === 'domain') {
      if (cleanTarget === scopeTarget) {
        return { allowed: true };
      }
    } else if (scope.type === 'ip') {
      if (cleanTarget === scopeTarget) {
        return { allowed: true };
      }
    } else if (scope.type === 'cidr') {
      try {
        if (/^\d{1,3}(\.\d{1,3}){3}$/.test(cleanTarget) && isIpInCidr(cleanTarget, scopeTarget)) {
          return { allowed: true };
        }
      } catch (e) {
        // Ignora erro de parsing
      }
    }
  }
  return { allowed: false, reason: `Target ${target} não está autorizado no escopo do projeto.` };
}

module.exports = { validateTargetAgainstScope };

