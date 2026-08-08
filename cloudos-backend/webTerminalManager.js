// cloudos-backend/webTerminalManager.js
const { spawn } = require('child_process');

const terminals = {};

function createTerminal(userId, ws, cols, rows) {
    if (terminals[userId]) {
        try { terminals[userId].kill(); } catch (e) {}
    }

    try {
        // Tenta spawnar o WSL via process child_process isolado
        const wslPath = 'C:\\Windows\\System32\\wsl.exe';
        const shell = spawn(wslPath, ['-e', 'bash', '-l']);
        terminals[userId] = shell;

        shell.stdout.on('data', (data) => {
            if (ws && ws.send) {
                ws.send(JSON.stringify({ type: 'terminal_output', data: data.toString() }));
            }
        });

        shell.stderr.on('data', (data) => {
            if (ws && ws.send) {
                ws.send(JSON.stringify({ type: 'terminal_output', data: data.toString() }));
            }
        });

        shell.on('error', (err) => {
            if (ws && ws.send) {
                ws.send(JSON.stringify({ type: 'terminal_error', data: `Erro ao iniciar WSL: ${err.message}` }));
            }
        });

        shell.on('close', () => {
            if (ws && ws.send) {
                ws.send(JSON.stringify({ type: 'terminal_exit' }));
            }
            delete terminals[userId];
        });

    } catch (err) {
        console.error("Erro PTY/WSL:", err);
        if (ws && ws.send) {
            ws.send(JSON.stringify({ type: 'terminal_error', data: err.message }));
        }
    }
}

function writeTerminal(userId, data) {
    if (terminals[userId] && terminals[userId].stdin) {
        try {
            terminals[userId].stdin.write(data);
        } catch (e) {}
    }
}

function resizeTerminal(userId, cols, rows) {
    // Sizing handling if needed
}

module.exports = { createTerminal, writeTerminal, resizeTerminal };
