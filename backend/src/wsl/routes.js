import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { authenticateToken, requireAdmin } from '../middleware/auth.js';
import { createOperation, getActiveOperation, runProcessOperation } from '../operations/operationManager.js';
import {
  POWERSHELL_EXE,
  WSL_EXE,
  createInstallArgs,
  getWslSnapshot,
  isCatalogDistro,
  listOnlineCatalog,
  normalizeName,
  setDefaultDistribution,
  startDistribution,
  stopDistribution,
  validateInstalledAsync
} from './distroService.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BROKER_SCRIPT = path.resolve(__dirname, '../../../scripts/cloudos-wsl-broker.ps1');
const WSL_MUTATION_TYPES = ['wsl_install', 'wsl_update', 'wsl_convert'];

export const wslRouter = express.Router();
wslRouter.use(authenticateToken);

wslRouter.get('/distributions', async (_req, res) => {
  const snapshot = await getWslSnapshot();
  res.status(snapshot.operational ? 200 : 503).json({
    available: snapshot.operational && snapshot.distributions.length > 0,
    installed: snapshot.installed,
    operational: snapshot.operational,
    errorCode: snapshot.errorCode,
    error: snapshot.error,
    default: snapshot.default,
    preferred: snapshot.preferred,
    distributions: snapshot.distributions
  });
});

wslRouter.get('/catalog', async (_req, res) => {
  try {
    res.json({ distributions: await listOnlineCatalog() });
  } catch (error) {
    res.status(error.code === 'WSL_ACCESS_DENIED' ? 403 : 503).json({
      error: error.message,
      errorCode: error.code || 'WSL_CATALOG_FAILED'
    });
  }
});

wslRouter.post('/installations', requireAdmin, async (req, res) => {
  const distribution = normalizeName(req.body?.distribution);
  const webDownload = req.body?.webDownload === true;
  try {
    const active = getActiveOperation(WSL_MUTATION_TYPES);
    if (active) return res.status(409).json({ error: 'Outra alteração do WSL já está em andamento.', operation: active });
    if (!await isCatalogDistro(distribution)) {
      return res.status(400).json({ error: 'A distribuição não pertence ao catálogo retornado pelo WSL.' });
    }
    const activeAfterPreflight = getActiveOperation(WSL_MUTATION_TYPES);
    if (activeAfterPreflight) return res.status(409).json({ error: 'Outra alteração do WSL já está em andamento.', operation: activeAfterPreflight });
    createInstallArgs(distribution);
    const operation = createOperation('wsl_install', distribution, `Preparando a instalação de ${distribution}...`);
    const brokerArgs = [
      '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', BROKER_SCRIPT,
      '-Action', 'Install',
      '-Distro', distribution
    ];
    if (webDownload) brokerArgs.push('-WebDownload');
    runProcessOperation(operation, POWERSHELL_EXE, brokerArgs, {
      step: 'installing',
      message: `Instalando ${distribution}. O Windows pode solicitar confirmação administrativa.`,
      successMessage: `${distribution} foi instalada. Abra o terminal para concluir o primeiro acesso.`,
      onSuccess: async () => {
        const snapshot = await getWslSnapshot();
        if (!snapshot.distributions.some((item) => item.name.toLowerCase() === distribution.toLowerCase())) {
          throw new Error('O instalador terminou, mas a distribuição ainda não aparece no inventário do WSL.');
        }
      }
    });
    res.location(`/api/operations/${operation.id}`).status(202).json({ operationId: operation.id, operation });
  } catch (error) {
    res.status(error.code === 'WSL_ACCESS_DENIED' ? 403 : 503).json({ error: error.message, errorCode: error.code || 'WSL_INSTALL_PRECHECK_FAILED' });
  }
});

wslRouter.post('/update', requireAdmin, async (_req, res) => {
  const active = getActiveOperation(WSL_MUTATION_TYPES);
  if (active) return res.status(409).json({ error: 'Outra alteração do WSL já está em andamento.', operation: active });
  const operation = createOperation('wsl_update', 'WSL', 'Preparando atualização do WSL e WSLg...');
  runProcessOperation(operation, POWERSHELL_EXE, [
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', BROKER_SCRIPT,
    '-Action', 'Update'
  ], {
    step: 'updating',
    message: 'Atualizando o WSL e o WSLg. O Windows pode solicitar confirmação administrativa.',
    successMessage: 'WSL e WSLg foram atualizados.'
  });
  res.location(`/api/operations/${operation.id}`).status(202).json({ operationId: operation.id, operation });
});

wslRouter.post('/distributions/:name/start', requireAdmin, async (req, res) => {
  try {
    const pid = await startDistribution(req.params.name);
    res.status(202).json({ status: 'starting', pid });
  } catch (error) {
    res.status(400).json({ error: error.message, errorCode: error.code });
  }
});

wslRouter.post('/distributions/:name/stop', requireAdmin, async (req, res) => {
  try {
    await stopDistribution(req.params.name);
    res.json({ status: 'stopped' });
  } catch (error) {
    res.status(400).json({ error: error.message, errorCode: error.code });
  }
});

wslRouter.post('/distributions/:name/set-default', requireAdmin, async (req, res) => {
  try {
    await setDefaultDistribution(req.params.name);
    res.json({ status: 'default', distribution: req.params.name });
  } catch (error) {
    res.status(400).json({ error: error.message, errorCode: error.code });
  }
});

wslRouter.post('/distributions/:name/set-version', requireAdmin, async (req, res) => {
  const distribution = normalizeName(req.params.name);
  const version = Number(req.body?.version);
  if (![1, 2].includes(version) || !await validateInstalledAsync(distribution)) {
    return res.status(400).json({ error: 'Distribuição ou versão inválida.' });
  }
  const active = getActiveOperation(WSL_MUTATION_TYPES);
  if (active) return res.status(409).json({ error: 'Outra alteração do WSL já está em andamento.', operation: active });
  const operation = createOperation('wsl_convert', distribution, `Preparando conversão para WSL ${version}...`);
  runProcessOperation(operation, WSL_EXE, ['--set-version', distribution, String(version)], {
    step: 'converting',
    message: `Convertendo ${distribution} para WSL ${version}...`,
    successMessage: `${distribution} agora usa WSL ${version}.`
  });
  res.location(`/api/operations/${operation.id}`).status(202).json({ operationId: operation.id, operation });
});