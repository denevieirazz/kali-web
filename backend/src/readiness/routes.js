import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import {
  InvalidReadinessProfileError,
  READINESS_PROFILES,
  readinessService
} from './readinessService.js';

export function createReadinessRouter(service = readinessService) {
  const router = express.Router();

  router.use(authenticateToken);

  router.get('/', async (req, res, next) => {
    const requestedProfile = req.query.profile ?? 'hybrid-dev';
    if (typeof requestedProfile !== 'string' || !READINESS_PROFILES.includes(requestedProfile)) {
      return res.status(400).json({
        error: 'Perfil de prontidão inválido.',
        allowedProfiles: READINESS_PROFILES
      });
    }

    try {
      const report = await service.getReport(requestedProfile, {
        localAddress: req.socket.localAddress || null
      });
      return res.status(200).json(report);
    } catch (error) {
      if (error instanceof InvalidReadinessProfileError || error?.code === 'INVALID_READINESS_PROFILE') {
        return res.status(400).json({
          error: 'Perfil de prontidão inválido.',
          allowedProfiles: READINESS_PROFILES
        });
      }
      return next(error);
    }
  });

  return router;
}

export const readinessRouter = createReadinessRouter();
