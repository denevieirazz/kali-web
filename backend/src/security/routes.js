import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { getKaliToolInventory } from './toolInventory.js';
import {
  getLocalNetworkOverview,
  getWifiDiagnostics,
  publicNetworkAssessmentPresets,
  runNetworkAssessment,
} from './networkAssessment.js';
import { getNetworkDiagnostics } from './networkDiagnostics.js';
import { getHostDiagnostics } from './hostDiagnostics.js';
import { getLocalNetworkPosture } from './localNetworkPosture.js';
import { inspectDnsName } from './dnsInspector.js';
import { inspectPublicWebUrl } from './webInspector.js';
import { enrichNetworkAssessment } from './networkInsights.js';
import { enrichWifiDiagnostics } from './wifiInsights.js';

export const securityToolsRouter = express.Router();
securityToolsRouter.use(authenticateToken);

securityToolsRouter.get('/', async (req, res) => {
  try {
    const inventory = await getKaliToolInventory(req.query.distribution);
    res.status(inventory.operational ? 200 : 503).json(inventory);
  } catch (error) {
    const status = error.code === 'DISTRO_NOT_INSTALLED' ? 404 : 503;
    res.status(status).json({
      error: error.message || 'Não foi possível consultar as ferramentas.',
      errorCode: error.code || 'TOOL_INVENTORY_FAILED'
    });
  }
});

securityToolsRouter.get('/network/overview', (_req, res) => {
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

securityToolsRouter.get('/network/diagnostics', async (_req, res) => {
  try {
    res.json(await getNetworkDiagnostics());
  } catch {
    res.status(503).json({
      error: 'Não foi possível coletar o mapa local de DNS, gateway e vizinhos.',
      errorCode: 'NETWORK_DIAGNOSTICS_FAILED',
    });
  }
});

securityToolsRouter.get('/network/local-posture', async (_req, res) => {
  try {
    res.json(await getLocalNetworkPosture());
  } catch {
    res.status(503).json({
      error: 'Não foi possível coletar a postura de rede local do Windows.',
      errorCode: 'LOCAL_NETWORK_POSTURE_FAILED',
    });
  }
});

securityToolsRouter.post('/network/dns/lookup', async (req, res) => {
  try {
    res.json(await inspectDnsName(req.body?.name));
  } catch (error) {
    const status = error.code === 'INVALID_DNS_NAME' ? 400 : 503;
    res.status(status).json({
      error: error.message || 'Falha na consulta DNS.',
      errorCode: error.code || 'DNS_INSPECTION_FAILED',
    });
  }
});

securityToolsRouter.post('/network/host/diagnostics', async (req, res) => {
  try {
    res.json(await getHostDiagnostics(req.body?.target));
  } catch (error) {
    const clientErrors = new Set([
      'INVALID_ASSESSMENT_TARGET', 'TARGET_OUTSIDE_LOCAL_SCOPE', 'CIDR_NOT_ALLOWED',
      'INVALID_CIDR', 'CIDR_TOO_LARGE',
    ]);
    const status = clientErrors.has(error.code) ? 400 : 503;
    res.status(status).json({
      error: error.message || 'Falha no diagnóstico do dispositivo local.',
      errorCode: error.code || 'HOST_DIAGNOSTICS_FAILED',
    });
  }
});

securityToolsRouter.get('/network/wifi', async (_req, res) => {
  try {
    res.json(enrichWifiDiagnostics(await getWifiDiagnostics()));
  } catch {
    res.status(503).json({ error: 'Não foi possível coletar o diagnóstico Wi‑Fi local.', errorCode: 'WIFI_DIAGNOSTICS_FAILED' });
  }
});

securityToolsRouter.post('/network/scan', async (req, res) => {
  const startedAt = new Date().toISOString();
  const started = Date.now();
  try {
    const result = await runNetworkAssessment({
      preset: req.body?.preset,
      target: req.body?.target,
      distribution: req.body?.distribution,
    });
    res.json(enrichNetworkAssessment({
      ...result,
      startedAt,
      durationMs: Date.now() - started,
      policy: {
        scope: 'private-local-only',
        arbitraryArguments: false,
        credentialAttacks: false,
        activeWirelessAttacks: false,
      },
    }));
  } catch (error) {
    const clientErrors = new Set([
      'INVALID_ASSESSMENT_TARGET', 'TARGET_OUTSIDE_LOCAL_SCOPE', 'CIDR_NOT_ALLOWED',
      'INVALID_CIDR', 'CIDR_TOO_LARGE', 'UNKNOWN_ASSESSMENT_PRESET',
    ]);
    const status = clientErrors.has(error.code) ? 400 : error.code === 'DISTRO_NOT_INSTALLED' ? 404 : 503;
    res.status(status).json({ error: error.message || 'Falha na avaliação de rede.', errorCode: error.code || 'NETWORK_ASSESSMENT_FAILED' });
  }
});

securityToolsRouter.post('/web/inspect', async (req, res) => {
  try {
    res.json(await inspectPublicWebUrl(req.body?.url));
  } catch (error) {
    const clientErrors = new Set([
      'INVALID_WEB_URL', 'WEB_SCHEME_NOT_ALLOWED', 'WEB_CREDENTIALS_NOT_ALLOWED',
      'WEB_PORT_NOT_ALLOWED', 'WEB_TARGET_NOT_PUBLIC', 'WEB_REDIRECT_INVALID',
    ]);
    const status = clientErrors.has(error.code) ? 400 : 503;
    res.status(status).json({
      error: error.message || 'Falha na inspeção web.',
      errorCode: error.code || 'WEB_INSPECTION_FAILED',
    });
  }
});
