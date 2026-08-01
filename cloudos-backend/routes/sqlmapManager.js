const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const { spawn } = require('child_process');
const { EventEmitter } = require('events');

const JWT_SECRET = process.env.JWT_SECRET || 'cloudos_secret_key';

const authMiddleware = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) return res.status(401).json({ error: 'Token não fornecido' });
  try { jwt.verify(token, JWT_SECRET); next(); } catch (err) { return res.status(401).json({ error: 'Token inválido' }); }
};

router.use(authMiddleware);

const activeScans = {};

// Dicionário de Tradução Tático (Inglês -> Português)
const PT_TRANSLATIONS = [
  { regex: /\[INFO\]/g, text: '[INFO]' },
  { regex: /\[WARNING\]/g, text: '[AVISO]' },
  { regex: /\[CRITICAL\]/g, text: '[CRÍTICO]' },
  { regex: /back-end DBMS:/g, text: 'Banco de Dados back-end:' },
  { regex: /is vulnerable/g, text: 'é vulnerável' },
  { regex: /appears to be injectable/g, text: 'parece ser injetável' },
  { regex: /Do you want to store hashes/g, text: 'Você deseja armazenar os hashes' },
  { regex: /for eventual further processing/g, text: 'para processamento futuro' },
  { regex: /Do you want to crack them/g, text: 'Você deseja quebrá-los' },
  { regex: /via a dictionary-based attack/g, text: 'via ataque de dicionário' },
  { regex: /available databases/g, text: 'bancos de dados disponíveis' },
  { regex: /Testing for SQL injection/g, text: 'Testando para SQL injection' },
  { regex: /Type:/g, text: 'Tipo:' },
  { regex: /Title:/g, text: 'Título:' },
  { regex: /Payload:/g, text: 'Payload:' },
  { regex: /Target URL/g, text: 'URL Alvo' },
  { regex: /automatic redirect/g, text: 'redirecionamento automático' },
];

function translateText(text, lang) {
  if (lang !== 'pt') return text;
  let translated = text;
  PT_TRANSLATIONS.forEach(({ regex, text: replacement }) => {
    translated = translated.replace(regex, replacement);
  });
  return translated;
}

/**
 * POST /api/sqlmap/scan
 */
router.post('/scan', (req, res) => {
  const { url, lang } = req.body;

  if (!url) return res.status(400).json({ error: 'URL é obrigatória' });
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return res.status(400).json({ error: 'URL deve começar com http:// ou https://' });
  }

  const safeUrl = url.replace(/'/g, `'"'"'`);
  const scanId = Date.now().toString();
  
  const cmd = `sqlmap -u '${safeUrl}' --dbs --random-agent --flush-session`;
  const child = spawn('wsl', ['-d', 'kali-linux', '-u', 'cloudos', 'bash', '-c', cmd]);

  const emitter = new EventEmitter();
  activeScans[scanId] = { child, emitter, buffer: '', fullOutput: '', lang: lang || 'pt' };

  res.json({ scanId, message: 'Scan iniciado.' });
});

/**
 * GET /api/sqlmap/events/:scanId
 */
router.get('/events/:scanId', (req, res) => {
  const scan = activeScans[req.params.scanId];
  if (!scan) return res.status(404).end();

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  const onMessage = (data) => res.write(`event: message\ndata: ${JSON.stringify(data)}\n\n`);
  const onQuestion = (data) => res.write(`event: question\ndata: ${JSON.stringify(data)}\n\n`);
  const onDone = (data) => {
    res.write(`event: done\ndata: ${JSON.stringify(data)}\n\n`);
    res.end();
    delete activeScans[req.params.scanId];
  };

  scan.emitter.on('message', onMessage);
  scan.emitter.on('question', onQuestion);
  scan.emitter.on('done', onDone);

  req.on('close', () => {
    scan.emitter.off('message', onMessage);
    scan.emitter.off('question', onQuestion);
    scan.emitter.off('done', onDone);
  });

  scan.child.stdout.on('data', (chunk) => {
    const text = chunk.toString().replace(/\x1b\[[0-9;]*m/g, '');
    scan.fullOutput += text;
    scan.buffer += text;

    const questionMatch = scan.buffer.match(/(.*?)(\[[yYnN]\/[yYnN]\])\s*$/s);
    
    if (questionMatch && !scan.waitingForAnswer) {
      scan.waitingForAnswer = true;
      let promptText = questionMatch[1].replace(/\[INFO\].*\n/g, '').trim();
      
      promptText = translateText(promptText, scan.lang);
      
      scan.emitter.emit('question', {
        text: promptText || 'O SQLmap requer uma decisão:',
        prompt: questionMatch[2]
      });
      scan.buffer = '';
    } else if (!scan.waitingForAnswer) {
      const translatedLog = translateText(text, scan.lang);
      scan.emitter.emit('message', { text: translatedLog });
      scan.buffer = '';
    }
  });

  scan.child.stderr.on('data', (chunk) => {
    const text = chunk.toString().replace(/\x1b\[[0-9;]*m/g, '');
    scan.emitter.emit('message', { text: translateText(text, scan.lang) });
  });

  scan.child.on('close', (code) => {
    const result = parseSqlmapOutput(scan.fullOutput);
    scan.emitter.emit('done', result);
  });
});

/**
 * POST /api/sqlmap/answer/:scanId
 */
router.post('/answer/:scanId', (req, res) => {
  const scan = activeScans[req.params.scanId];
  if (!scan) return res.status(404).json({ error: 'Scan não encontrado' });

  const { answer } = req.body;
  scan.child.stdin.write(`${answer}\n`);
  scan.waitingForAnswer = false;
  
  res.json({ success: true });
});

function parseSqlmapOutput(stdout) {
  const result = { vulnerable: false, dbms: 'Desconhecido', databases: [], payload: null };
  
  if (/is vulnerable|appears to be injectable|injectable/i.test(stdout)) result.vulnerable = true;
  
  const dbmsMatch = stdout.match(/back-end DBMS:\s*(.+?)\n/i);
  if (dbmsMatch) result.dbms = dbmsMatch[1].trim();

  const payloadMatch = stdout.match(/Payload:\s*(.+?)\n/i);
  if (payloadMatch) result.payload = payloadMatch[1].trim();

  const dbsMatch = stdout.match(/available databases \[\d+\]:\s*([\s\S]*?)(\n\n|\n\[INFO\])/i);
  if (dbsMatch) {
    result.databases = dbsMatch[1].trim().split('\n')
      .map(db => db.replace(/^\[\*\]/, '').trim())
      .filter(db => db.length > 0 && !db.startsWith('['));
  }

  return result;
}

module.exports = router;
