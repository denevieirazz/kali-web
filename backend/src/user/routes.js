import express from 'express';
import { authenticateToken } from '../middleware/auth.js';

export const userRouter = express.Router();

userRouter.get('/state', authenticateToken, (req, res) => {
  res.json({
    user: req.user,
    preferences: {
      theme: 'dark',
      wallpaper: 'default.png',
      accentColor: '#6366f1'
    },
    status: 'active'
  });
});
