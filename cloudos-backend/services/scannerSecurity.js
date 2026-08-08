const database = require('../database');
const { validateTargetAgainstScope } = require('./scopeGuard');

// Catálogo Rígido de Ferramentas Autorizadas para Execução
const TOOL_ALLOWLIST = new Set([
  'nmap',
  'sqlmap',
  'nikto',
  'gobuster',
  'whois',
  'dnsenum',
  'theHarvester',
  'theharvester',
  'hydra',
  'john',
  'hashcat',
  'searchsploit',
  'msfconsole',
  'tshark',
  'tcpdump',
  'wpscan'
]);

/**
 * Valida o contexto do projeto, propriedade do usuário e escopo do alvo antes da execução.
 * Retorna { allowed, reason, project, scopes, sanitizedTarget }
 */
async function getProjectExecutionContext(userId, projectId, target) {
  if (!userId) {
    return { allowed: false, reason: 'Usuário não autenticado.' };
  }

  if (!projectId) {
    return { allowed: false, reason: 'Obrigatorio fornecer um Project Context (projectId).' };
  }

  const db = database;
  
  // 1. Valida propriedade do projeto
  const project = await db.prepare('SELECT * FROM projects WHERE id = ? AND user_id = ?').get(projectId, userId);
  if (!project) {
    return { allowed: false, reason: 'Projeto não encontrado ou acesso não autorizado.' };
  }

  // 2. Coleta escopos autorizados
  const scopes = await db.prepare('SELECT target, type FROM project_scopes WHERE project_id = ?').all(projectId);
  if (!scopes || scopes.length === 0) {
    return { allowed: false, reason: 'Projeto não possui escopos autorizados cadastrados.' };
  }

  // 3. Validação do Alvo contra os Escopos
  if (target) {
    let cleanTarget = String(target).trim();
    // Se for URL, extrai hostname para validar
    if (/^https?:\/\//i.test(cleanTarget)) {
      try {
        const u = new URL(cleanTarget);
        cleanTarget = u.hostname;
      } catch {
        return { allowed: false, reason: 'Formato de URL do alvo inválido.' };
      }
    }

    const scopeCheck = validateTargetAgainstScope(cleanTarget, scopes);
    if (!scopeCheck.allowed) {
      return { allowed: false, reason: scopeCheck.reason, project, scopes };
    }
  }

  return {
    allowed: true,
    project,
    scopes
  };
}

/**
 * Valida se uma ferramenta está explicitamente autorizada na allowlist.
 */
function isToolAllowed(toolName) {
  if (!toolName || typeof toolName !== 'string') return false;
  return TOOL_ALLOWLIST.has(toolName.trim().toLowerCase());
}

module.exports = {
  getProjectExecutionContext,
  isToolAllowed,
  TOOL_ALLOWLIST
};
