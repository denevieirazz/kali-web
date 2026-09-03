import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import {
  getLocalNetworkOverview,
  getWifiDiagnostics,
  publicNetworkAssessmentPresets,
  runNetworkAssessment,
} from './networkAssessment.js';

export const networkAssessmentRouter = express.Router();
networkAssessmentRouter.use(authenticateToken);

networkAssessmentRouter.get('/overview', (_req, res) => {
  res.json({
    ...getLocalNetworkOverview(),
    presets: publicNetworkAssessmentPresets(),
    policy: {
      scope: 'private-local-only',
      maxDiscoveryRange: '/24',
      arbitraryArguments: false,
      activeWirelessAttacks: false,
    },
  });
});

networkAssessmentRouter.get('/wifi', async (_req, res) => {
  try {
    res.json(await getWifiDiagnostics());
  } catch {
    res.status(503).json({ error: 'Não foi possível coletar o diagnóstico Wi‑Fi local.', errorCode: 'WIFI_DIAGNOSTICS_FAILED' });
  }
});

networkAssessmentRouter.post('/scan', async (req, res) => {
  try {
    const result = await runNetworkAssessment({
      preset: req.body?.preset,
      target: req.body?.target,
      distribution: req.body?.distribution,
    });
    res.json(result);
  } catch (error) {
    const clientErrors = new Set([
      'INVALID_ASSESSMENT_TARGET', 'TARGET_OUTSIDE_LOCAL_SCOPE', 'CIDR_NOT_ALLOWED',
      'INVALID_CIDR', 'CIDR_TOO_LARGE', 'UNKNOWN_ASSESSMENT_PRESET',
    ]);
    const status = clientErrors.has(error.code) ? 400 : error.code === 'DISTRO_NOT_INSTALLED' ? 404 : 503;
    res.status(status).json({ error: error.message || 'Falha na avaliação de rede.', errorCode: error.code || 'NETWORK_ASSESSMENT_FAILED' });
  }
});
