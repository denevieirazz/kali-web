import express from 'express';
import { authenticateToken } from '../middleware/auth.js';

export const userRouter = express.Router();

userRouter.get('/state', authenticateToken, (req, res) => {
  res.json({
    user: {
      id: req.user.userId,
      username: req.user.username,
      displayName: req.user.displayName,
      role: req.user.role
    },
    preferences: {
      theme: 'dark',
      wallpaper: 'default.png',
      accentColor: '#6366f1'
    },
    status: 'active'
  });
});
