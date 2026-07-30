const jwt = require('jsonwebtoken');
const SECRET_KEY = process.env.JWT_SECRET || 'cloudos_super_secret_jwt_key_2026';

async function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'Acesso negado. Token não fornecido.' });
    
    jwt.verify(token, SECRET_KEY, async (err, decoded) => {
        if (err) return res.status(403).json({ error: 'Token inválido ou expirado.' });
        
        try {
            const db = req.app.get('db');
            let userId = decoded.id;
            let dbUser = await db.prepare('SELECT * FROM users WHERE id = ?').get(String(userId));
            
            if (!dbUser && (decoded.username === 'admin' || String(userId) === '1')) {
                dbUser = await db.prepare('SELECT * FROM users WHERE username = ?').get('admin');
                if (dbUser) userId = dbUser.id;
            }
            
            if (!dbUser) {
                return res.status(401).json({ error: 'Sessão inválida. Faça login novamente.' });
            }
            
            req.user = { id: dbUser.id, username: dbUser.username, tier: dbUser.tier };
            next();
        } catch (e) {
            res.status(500).json({ error: 'Erro de validação de usuário.' });
        }
    });
}

module.exports = { authenticateToken };
