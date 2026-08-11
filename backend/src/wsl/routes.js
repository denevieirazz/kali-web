import express from 'express';
import { listInstalled, getDefault, getPreferred } from './distroService.js';

export const wslRouter = express.Router();

wslRouter.get('/distributions', (req, res) => {
  try {
    const distros = listInstalled();
    const defaultDistro = getDefault();
    const preferredDistro = getPreferred();

    res.json({
      available: distros.length > 0,
      default: defaultDistro,
      preferred: preferredDistro,
      distributions: distros.map(d => ({
        name: d.name,
        version: d.version,
        state: d.state
      }))
    });
  } catch (err) {
    res.json({
      available: false,
      default: null,
      preferred: null,
      distributions: []
    });
  }
});
