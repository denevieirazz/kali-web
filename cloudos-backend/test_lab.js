const http = require('http');

const PORT = 8090;

const server = http.createServer((req, res) => {
    let pathname = req.url || '/';
    let searchParams = new URLSearchParams();

    try {
        const parsed = new URL(req.url, `http://${req.headers.host || 'localhost:8090'}`);
        pathname = parsed.pathname;
        searchParams = parsed.searchParams;
    } catch (e) {
        // Fallback for scanner fuzzing like // or malformed URIs
        pathname = req.url.split('?')[0] || '/';
    }
    
    // Custom Headers for Nikto & WhatWeb detection
    res.setHeader('X-Powered-By', 'CloudOS-Test-Lab/1.0 (Express/Node.js)');
    res.setHeader('Server', 'Apache/2.4.41 (Unix) OpenSSL/1.1.1d');

    // Routing for testing tools
    if (pathname === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        return res.end(`
            <!DOCTYPE html>
            <html>
            <head><title>CloudOS Test Lab Target</title></head>
            <body>
                <h1>Alvo de Testes Local do CloudOS</h1>
                <p>Servidor HTTP de testes para Nmap, Gobuster, Nikto, Httpx, SQLMap e Commix.</p>
                <ul>
                    <li><a href="/admin">/admin</a> (Diretório restrito)</li>
                    <li><a href="/secret">/secret</a> (Área secreta)</li>
                    <li><a href="/page.php?id=1">/page.php?id=1</a> (Simulação SQL)</li>
                    <li><a href="/cmd.php?cmd=test">/cmd.php?cmd=test</a> (Simulação Command)</li>
                </ul>
            </body>
            </html>
        `);
    }

    if (pathname === '/admin' || pathname === '/secret' || pathname === '/api' || pathname === '/login.html') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        return res.end(`<h1>Página Encontrada: ${pathname}</h1>`);
    }

    if (pathname.includes('page.php')) {
        const id = searchParams.get('id') || '1';
        res.writeHead(200, { 'Content-Type': 'text/html' });
        return res.end(`<h1>Resultado para ID: ${id}</h1><p>Usuário: admin (ID: ${id})</p>`);
    }

    if (pathname.includes('cmd.php')) {
        const cmd = searchParams.get('cmd') || 'test';
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end(`Simulação de execução: ${cmd}`);
    }

    // Default 404
    res.writeHead(404, { 'Content-Type': 'text/html' });
    res.end('<h1>404 Not Found</h1>');
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`🎯 Alvo de Teste Local (CloudOS Test Lab) rodando em http://0.0.0.0:${PORT}`);
});
