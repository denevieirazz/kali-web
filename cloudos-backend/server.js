const express = require('express');
const { WebSocketServer } = require('ws');
const Docker = require('dockerode');
const cors = require('cors');

const app = express();
app.use(cors());
const server = require('http').createServer(app);
const wss = new WebSocketServer({ server });

// Conexão com Docker configurada para Windows e Linux/Mac
const isWindows = process.platform === 'win32';
const docker = new Docker(isWindows ? { socketPath: '\\\\.\\pipe\\docker_engine' } : undefined);

async function setupKaliContainer(userId) {
    const volumeName = `kali_hd_${userId}`;
    const containerName = `cloudos_kali_${userId}`;
    const imageName = 'kalilinux/kali-rolling:latest';
    
    // 1. Cria o HD virtual do usuário (ignora erro se já existir)
    try { 
        await docker.createVolume({ Name: volumeName }); 
    } catch (err) {}

    // 2. Garante que a imagem do Kali Linux existe localmente (faz pull se necessário)
    try {
        await docker.getImage(imageName).inspect();
    } catch (e) {
        console.log(`Baixando imagem do Kali Linux (${imageName})...`);
        await new Promise((resolve, reject) => {
            docker.pull(imageName, (err, stream) => {
                if (err) return reject(err);
                docker.modem.followProgress(stream, (err, output) => {
                    if (err) return reject(err);
                    resolve(output);
                });
            });
        });
    }

    let container = docker.getContainer(containerName);
    try {
        const info = await container.inspect();
        if (!info.State.Running) await container.start();
    } catch (err) {
        console.log("Criando e iniciando o container Kali Linux no Docker...");
        container = await docker.createContainer({
            Image: imageName,
            name: containerName,
            Cmd: ['/bin/bash'],
            Tty: true,
            OpenStdin: true,
            Env: ['TERM=xterm-256color'],
            HostConfig: {
                Binds: [`${volumeName}:/root`], // Salva os arquivos no HD virtual
                Memory: 2 * 1024 * 1024 * 1024, // 2GB de RAM
                NanoCpus: 2000000000, // 2 núcleos de CPU
                NetworkMode: 'bridge'
            }
        });
        await container.start();
        console.log("Kali Linux iniciado com sucesso!");
    }
    return container;
}

// 🔄 Sistema de Heartbeat (Ping/Pong) para detectar conexões mortas
function heartbeat() {
    this.isAlive = true;
}

const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) return ws.terminate();
        ws.isAlive = false;
        ws.ping();
    });
}, 30000); // Verifica a cada 30 segundos

wss.on('connection', async (ws, req) => {
    // Inicializa o heartbeat
    ws.isAlive = true;
    ws.on('pong', heartbeat);

    // Parse seguro da URL
    const fullUrl = new URL(req.url, 'http://localhost');
    const userId = fullUrl.searchParams.get('userId') || 'kali_user';

    let stream;
    let container;

    try {
        container = await setupKaliContainer(userId);
        const exec = await container.exec({
            Cmd: ['/bin/bash'],
            AttachStdin: true, 
            AttachStdout: true, 
            AttachStderr: true,
            Tty: true, 
            WorkingDir: '/root'
        });
        stream = await exec.start({ hijack: true, stdin: true });

        // 📥 Dados do Docker para o Navegador
        // Enviamos o Buffer puro para evitar quebra de caracteres UTF-8 no terminal
        stream.on('data', (chunk) => {
            if (ws.readyState === ws.OPEN) {
                ws.send(chunk);
            }
        });

        // Trata erros no stream do Docker (ex: container foi morto manualmente)
        stream.on('error', (err) => {
            console.error('Erro no stream do Docker:', err.message);
            if (ws.readyState === ws.OPEN) {
                ws.send(`\r\n\x1b[31m[ERRO] Conexão com o container perdida.\x1b[0m\r\n`);
                ws.close();
            }
        });

        // ⌨️ Comandos do Navegador para o Docker
        ws.on('message', (msg) => {
            if (stream.writable) {
                stream.write(msg);
            }
        });

        // 🚪 Ao fechar o navegador, para o container para economizar recursos
        ws.on('close', async () => {
            console.log(`Conexão fechada. Parando container do usuário ${userId}...`);
            try {
                if (stream) stream.end();
                if (container) await container.stop({ t: 2 }); // Espera 2s antes de matar (graceful shutdown)
            } catch (e) {
                // Ignora erro se o container já estiver parado
            }
        });

    } catch (error) {
        console.error("ERRO NO DOCKER:", error.message);
        if (ws.readyState === ws.OPEN) {
            ws.send("ERRO: O Docker Desktop precisa estar aberto e rodando no Windows (socket: \\\\.\\pipe\\docker_engine).\r\n");
            ws.close();
        }
    }
});

server.listen(8080, () => console.log('🚀 Backend CloudOS rodando! Aguardando conexões do Kali via Docker...'));
