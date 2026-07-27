const express = require('express');
const { WebSocketServer } = require('ws');
const Docker = require('dockerode');
const cors = require('cors');

const app = express();
app.use(cors());
const server = require('http').createServer(app);
const wss = new WebSocketServer({ server });

const isWindows = process.platform === 'win32';
const docker = new Docker(isWindows ? { socketPath: '\\\\.\\pipe\\docker_engine' } : undefined);

async function setupKaliContainer(userId) {
    const volumeName = `kali_hd_${userId}`;
    const containerName = `cloudos_kali_${userId}`;
    const imageName = 'kalilinux/kali-rolling:latest';
    
    try { await docker.createVolume({ Name: volumeName }); } catch (err) {}

    // Garante que a imagem do Kali Linux existe localmente (faz pull se necessário)
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
        console.log("Baixando/Iniciando o Kali Linux no Docker...");
        container = await docker.createContainer({
            Image: imageName,
            name: containerName,
            Cmd: ['/bin/bash'],
            Tty: true,
            OpenStdin: true,
            // 🚨 FORÇA O IDIOMA PORTUGUÊS E UTF-8 AQUI
            Env: [
                'TERM=xterm-256color',
                'LANG=pt_BR.UTF-8',
                'LANGUAGE=pt_BR:pt:en',
                'LC_ALL=pt_BR.UTF-8'
            ],
            HostConfig: {
                Binds: [`${volumeName}:/root`],
                Memory: 2 * 1024 * 1024 * 1024,
                NanoCpus: 2000000000,
                NetworkMode: 'bridge'
            }
        });
        await container.start();
        console.log("Kali Linux iniciado com sucesso!");

        // Auto-configura teclado br-abnt2 e locale no novo container
        try {
            const setupExec = await container.exec({
                Cmd: ['/bin/bash', '-c', 'apt update && apt install -y kbd locales && echo "loadkeys br-abnt2 2>/dev/null" >> /root/.bashrc && echo "export LANG=pt_BR.UTF-8" >> /root/.bashrc'],
                AttachStdout: true, AttachStderr: true
            });
            await setupExec.start({});
        } catch (e) {}
    }
    return container;
}

function heartbeat() {
    this.isAlive = true;
}

const interval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) return ws.terminate();
        ws.isAlive = false;
        ws.ping();
    });
}, 30000);

wss.on('connection', async (ws, req) => {
    ws.isAlive = true;
    ws.on('pong', heartbeat);

    const fullUrl = new URL(req.url, 'http://localhost');
    const userId = fullUrl.searchParams.get('userId') || 'kali_user';

    let stream;
    let container;
    let exec;

    try {
        container = await setupKaliContainer(userId);
        exec = await container.exec({
            Cmd: ['/bin/bash'],
            AttachStdin: true, 
            AttachStdout: true, 
            AttachStderr: true,
            Tty: true, 
            WorkingDir: '/root',
            // 🚨 FORÇA O IDIOMA NA SESSÃO DO TERMINAL TAMBÉM
            Env: [
                'TERM=xterm-256color',
                'LANG=pt_BR.UTF-8',
                'LANGUAGE=pt_BR:pt:en',
                'LC_ALL=pt_BR.UTF-8'
            ]
        });
        stream = await exec.start({ hijack: true, stdin: true });

        stream.on('data', (chunk) => {
            if (ws.readyState === ws.OPEN) {
                ws.send(chunk);
            }
        });

        stream.on('error', (err) => {
            console.error('Erro no stream do Docker:', err.message);
            if (ws.readyState === ws.OPEN) {
                ws.send(`\r\n\x1b[31m[ERRO] Conexão com o container perdida.\x1b[0m\r\n`);
                ws.close();
            }
        });

        ws.on('message', (msg) => {
            const strMsg = msg.toString();
            
            if (strMsg.startsWith('{"type":"resize"')) {
                try {
                    const data = JSON.parse(strMsg);
                    if (data.type === 'resize' && exec) {
                        exec.resize({ h: data.rows, w: data.cols }, () => {});
                    }
                } catch (e) {}
            } else {
                if (stream && stream.writable) stream.write(msg);
            }
        });

        ws.on.call ? null : null; // Keep event structure intact
        ws.on('close', async () => {
            console.log(`Conexão fechada. Parando container do usuário ${userId}...`);
            try {
                if (stream) stream.end();
                if (container) await container.stop({ t: 2 });
            } catch (e) {}
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
