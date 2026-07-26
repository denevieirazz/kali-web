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
    
    // 1. Cria o HD virtual do usuário
    try { await docker.createVolume({ Name: volumeName }); } catch (err) {}

    let container = docker.getContainer(containerName);
    try {
        const info = await container.inspect();
        if (!info.State.Running) await container.start();
    } catch (err) {
        console.log("Baixando/Iniciando o Kali Linux no Docker...");
        // 2. Cria o container com a imagem oficial do Kali Linux
        container = await docker.createContainer({
            Image: 'kalilinux/kali-rolling:latest',
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

wss.on('connection', async (ws, req) => {
    const params = new URLSearchParams(req.url.split('?')[1]);
    const userId = params.get('userId') || 'kali_user';

    try {
        const container = await setupKaliContainer(userId);
        const exec = await container.exec({
            Cmd: ['/bin/bash'],
            AttachStdin: true, AttachStdout: true, AttachStderr: true,
            Tty: true, WorkingDir: '/root'
        });
        const stream = await exec.start({ hijack: true, stdin: true });

        ws.on('message', (msg) => stream.write(msg));
        stream.on('data', (chunk) => ws.send(chunk.toString('utf-8')));

        ws.on('close', async () => {
            try { await container.stop(); } catch (e) {}
        });
    } catch (error) {
        console.error("ERRO NO DOCKER:", error.message);
        ws.send("ERRO: O Docker Desktop precisa estar aberto e rodando no Windows (socket: \\\\.\\pipe\\docker_engine).\r\n");
    }
});

server.listen(8080, () => console.log('🚀 Backend CloudOS rodando! Aguardando conexões do Kali via Docker...'));
