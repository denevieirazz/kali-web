// cloudos-backend/akbManager.js
const xml2js = require('xml2js');
const database = require('./database');
const rawDb = database.rawDb;

const parser = new xml2js.Parser({ explicitArray: false });

/**
 * Faz o parse do XML do Nmap e salva no banco de dados SQLite
 * @param {string} xmlOutput - A saída XML do Nmap
 * @param {number} projectId - ID do projeto atual
 */
async function parseAndSaveNmap(xmlOutput, projectId = 1) {
  try {
    const result = await parser.parseStringPromise(xmlOutput);
    if (!result || !result.nmaprun || !result.nmaprun.host) return;

    const hosts = Array.isArray(result.nmaprun.host) ? result.nmaprun.host : [result.nmaprun.host];

    for (const host of hosts) {
      const address = host.address && host.address.$ && host.address.$.addr ? host.address.$.addr : 'Desconhecido';
      const status = host.status && host.status.$ && host.status.$.state ? host.status.$.state : 'unknown';
      
      let hostname = null;
      if (host.hostnames && host.hostnames.hostname) {
        if (Array.isArray(host.hostnames.hostname)) {
          hostname = host.hostnames.hostname[0]?.$?.name;
        } else if (host.hostnames.hostname.$) {
          hostname = host.hostnames.hostname.$.name;
        }
      }

      // 1. Inserir ou Atualizar Host
      rawDb.run(
        `INSERT INTO akb_hosts (project_id, ip, hostname, status, last_scanned) 
         VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(project_id, ip) DO UPDATE SET status=excluded.status, last_scanned=CURRENT_TIMESTAMP`,
        [projectId, address, hostname, status],
        function (err) {
          if (err) return console.error('Erro ao salvar host AKB:', err);
          
          const hostId = this.lastID;
          
          // 2. Inserir Portas (se existirem)
          if (host.ports && host.ports.port) {
            const ports = Array.isArray(host.ports.port) ? host.ports.port : [host.ports.port];
            
            ports.forEach(port => {
              const portNum = port.$?.portid || 0;
              const protocol = port.$?.protocol || 'tcp';
              const state = port.state && port.state.$ && port.state.$.state ? port.state.$.state : 'unknown';
              const service = port.service && port.service.$ && port.service.$.name ? port.service.$.name : 'unknown';
              const version = port.service && port.service.$ && port.service.$.version ? port.service.$.version : '';
              
              rawDb.run(
                `INSERT INTO akb_ports (host_id, port, protocol, state, service, version)
                 VALUES (?, ?, ?, ?, ?, ?)`,
                [hostId, portNum, protocol, state, service, version]
              );
            });
          }
        }
      );
    }
  } catch (error) {
    console.error('Erro ao fazer parse do XML Nmap:', error);
  }
}

module.exports = { parseAndSaveNmap };
