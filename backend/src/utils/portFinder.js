import net from 'net';

export async function findFreePort(startPort = 18080, maxPort = 18180, host = '127.0.0.1') {
  for (let port = startPort; port <= maxPort; port++) {
    const isFree = await new Promise((resolve) => {
      const server = net.createServer();
      server.unref();
      server.on('error', () => {
        resolve(false);
      });
      server.listen(port, host, () => {
        server.close(() => {
          resolve(true);
        });
      });
    });

    if (isFree) {
      return port;
    }
  }

  throw new Error(`Nenhuma porta livre encontrada na faixa ${startPort}-${maxPort} em ${host}`);
}
