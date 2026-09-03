export type PortKnowledge = {
  title: string;
  category: string;
  explanation: string;
  review: string;
};

const PORTS: Record<number, PortKnowledge> = {
  21: { title: 'FTP', category: 'arquivos', explanation: 'Transferência de arquivos. Pode ser legado em ambientes modernos.', review: 'Confirme se ainda é necessário e se dados sensíveis usam uma alternativa protegida.' },
  22: { title: 'SSH', category: 'administração', explanation: 'Acesso remoto seguro e SFTP em muitos servidores Linux/Unix.', review: 'Confirme proprietário, necessidade e política de acesso administrativo.' },
  23: { title: 'Telnet', category: 'administração', explanation: 'Acesso remoto legado normalmente sem proteção moderna do tráfego.', review: 'Revise com prioridade se Telnet ainda precisa existir na rede.' },
  25: { title: 'SMTP', category: 'e-mail', explanation: 'Transporte de e-mail entre servidores.', review: 'Confirme se o host realmente deveria oferecer SMTP e revise política de relay.' },
  53: { title: 'DNS', category: 'infraestrutura', explanation: 'Resolução de nomes da rede.', review: 'Confirme se o dispositivo é um DNS autorizado e se a exposição corresponde ao desenho da rede.' },
  80: { title: 'HTTP', category: 'web', explanation: 'Serviço web sem TLS na própria conexão.', review: 'Abra o Web Inspector e confirme redirect para HTTPS ou justificativa para HTTP.' },
  88: { title: 'Kerberos', category: 'identidade', explanation: 'Autenticação comum em ambientes Active Directory.', review: 'Confirme se o host é controlador/serviço de identidade esperado.' },
  110: { title: 'POP3', category: 'e-mail', explanation: 'Recebimento de e-mail por protocolo legado sem TLS implícito.', review: 'Confirme se ainda é necessário e se existe proteção adequada.' },
  123: { title: 'NTP', category: 'infraestrutura', explanation: 'Sincronização de horário.', review: 'Confirme se este host deve fornecer horário para outros equipamentos.' },
  135: { title: 'RPC Windows', category: 'windows', explanation: 'Endpoint mapper usado por vários serviços Windows.', review: 'Confirme se a exposição é necessária no segmento e revise firewall.' },
  137: { title: 'NetBIOS Name', category: 'windows', explanation: 'Descoberta/nomeação NetBIOS legada.', review: 'Revise necessidade em redes modernas e segmentação.' },
  138: { title: 'NetBIOS Datagram', category: 'windows', explanation: 'Componente legado de comunicação NetBIOS.', review: 'Revise necessidade e alcance do segmento.' },
  139: { title: 'NetBIOS Session', category: 'windows', explanation: 'Compartilhamento Windows legado sobre NetBIOS.', review: 'Confirme necessidade e limite exposição por firewall/segmentação.' },
  143: { title: 'IMAP', category: 'e-mail', explanation: 'Acesso a caixas de e-mail sem TLS implícito.', review: 'Confirme se TLS é aplicado por upgrade de conexão ou prefira IMAPS.' },
  161: { title: 'SNMP', category: 'gerenciamento', explanation: 'Monitoramento e gerenciamento de dispositivos.', review: 'Confirme versão/configuração e se o host deveria responder neste segmento.' },
  389: { title: 'LDAP', category: 'identidade', explanation: 'Diretório e identidade, comum em Active Directory.', review: 'Confirme se o host é serviço de diretório esperado e revise proteção do canal.' },
  443: { title: 'HTTPS', category: 'web', explanation: 'Serviço web protegido por TLS.', review: 'Abra o Web Inspector para revisar certificado, headers e cookies.' },
  445: { title: 'SMB', category: 'windows', explanation: 'Compartilhamento de arquivos/impressoras e vários fluxos Windows.', review: 'Confirme necessidade, proprietário e alcance; revise firewall e segmentação.' },
  465: { title: 'SMTPS', category: 'e-mail', explanation: 'SMTP com TLS implícito.', review: 'Confirme que o serviço é esperado e mantido.' },
  554: { title: 'RTSP', category: 'multimídia/IoT', explanation: 'Streaming comum em câmeras e equipamentos de vídeo.', review: 'Confirme se é câmera/dispositivo esperado e se a rede está segmentada.' },
  587: { title: 'SMTP Submission', category: 'e-mail', explanation: 'Envio autenticado de e-mail por clientes.', review: 'Confirme se o host deve aceitar submissão neste segmento.' },
  631: { title: 'IPP', category: 'impressão', explanation: 'Impressão em rede e administração de impressoras.', review: 'Confirme se é servidor/impressora esperado e limite administração.' },
  636: { title: 'LDAPS', category: 'identidade', explanation: 'LDAP protegido por TLS.', review: 'Confirme identidade do serviço e validade da configuração TLS.' },
  993: { title: 'IMAPS', category: 'e-mail', explanation: 'IMAP protegido por TLS.', review: 'Confirme se o host é servidor de e-mail esperado.' },
  995: { title: 'POP3S', category: 'e-mail', explanation: 'POP3 protegido por TLS.', review: 'Confirme se o serviço ainda é necessário.' },
  1433: { title: 'SQL Server', category: 'banco', explanation: 'Porta comum do Microsoft SQL Server.', review: 'Confirme se clientes deste segmento realmente precisam alcançar o banco.' },
  1521: { title: 'Oracle DB', category: 'banco', explanation: 'Listener comum de Oracle Database.', review: 'Confirme necessidade de exposição e segmentação do banco.' },
  1883: { title: 'MQTT', category: 'IoT', explanation: 'Mensageria muito usada em dispositivos IoT.', review: 'Confirme se broker/dispositivo é esperado e se autenticação/TLS são exigidos.' },
  2049: { title: 'NFS', category: 'arquivos', explanation: 'Compartilhamento de arquivos típico de Unix/Linux.', review: 'Confirme clientes permitidos e segmentação.' },
  3000: { title: 'Web Dev 3000', category: 'desenvolvimento', explanation: 'Porta frequente de servidores de desenvolvimento.', review: 'Confirme se ambiente de desenvolvimento deveria estar acessível na rede.' },
  3306: { title: 'MySQL/MariaDB', category: 'banco', explanation: 'Banco MySQL/MariaDB.', review: 'Confirme se acesso direto ao banco é necessário neste segmento.' },
  3389: { title: 'RDP', category: 'administração', explanation: 'Área de Trabalho Remota do Windows.', review: 'Confirme quem administra o host e restrinja acesso à rede administrativa quando possível.' },
  4200: { title: 'Web Dev 4200', category: 'desenvolvimento', explanation: 'Porta frequente de servidores Angular/dev.', review: 'Confirme se é temporário e se deveria estar exposto além da máquina do desenvolvedor.' },
  5000: { title: 'Web/App 5000', category: 'desenvolvimento', explanation: 'Porta comum de Flask e outros servidores locais.', review: 'Confirme se é ambiente de desenvolvimento ou serviço intencional.' },
  5173: { title: 'Vite Dev', category: 'desenvolvimento', explanation: 'Porta padrão comum do servidor de desenvolvimento Vite.', review: 'Confirme se o dev server deveria estar acessível pela rede.' },
  5432: { title: 'PostgreSQL', category: 'banco', explanation: 'Banco PostgreSQL.', review: 'Confirme necessidade de acesso direto e segmentação.' },
  5900: { title: 'VNC', category: 'administração', explanation: 'Controle remoto gráfico VNC.', review: 'Confirme necessidade, proprietário e proteção do acesso.' },
  5901: { title: 'VNC alternativo', category: 'administração', explanation: 'Sessão VNC adicional/alternativa.', review: 'Confirme necessidade e limite a redes administrativas.' },
  5985: { title: 'WinRM HTTP', category: 'administração', explanation: 'Gerenciamento remoto do Windows por HTTP.', review: 'Confirme uso administrativo e política de firewall.' },
  5986: { title: 'WinRM HTTPS', category: 'administração', explanation: 'Gerenciamento remoto do Windows protegido por TLS.', review: 'Confirme necessidade e identidade do serviço.' },
  6379: { title: 'Redis', category: 'cache/banco', explanation: 'Cache/banco Redis.', review: 'Confirme se aplicações deste segmento precisam acesso direto.' },
  8000: { title: 'Web 8000', category: 'web/desenvolvimento', explanation: 'Porta alternativa comum para aplicações web.', review: 'Abra no Web Inspector se for HTTP/HTTPS e confirme finalidade.' },
  8080: { title: 'Web 8080', category: 'web', explanation: 'HTTP alternativo comum em proxies, painéis e aplicações.', review: 'Abra no Web Inspector e confirme se é painel administrativo ou aplicação esperada.' },
  8081: { title: 'Web 8081', category: 'web/desenvolvimento', explanation: 'Porta alternativa comum de aplicações e ferramentas de desenvolvimento.', review: 'Confirme finalidade e se o acesso precisa ser amplo.' },
  8443: { title: 'HTTPS 8443', category: 'web', explanation: 'HTTPS alternativo comum em painéis e appliances.', review: 'Abra no Web Inspector para revisar certificado e headers.' },
  8888: { title: 'Web/Jupyter 8888', category: 'web/desenvolvimento', explanation: 'Porta frequente de notebooks e aplicações web auxiliares.', review: 'Confirme se é ferramenta de desenvolvimento e se precisa ficar acessível.' },
  9000: { title: 'Painel/Dev 9000', category: 'desenvolvimento', explanation: 'Porta usada por diversos painéis e serviços de desenvolvimento.', review: 'Identifique o serviço e confirme exposição intencional.' },
  9100: { title: 'JetDirect', category: 'impressão', explanation: 'Impressão RAW comum em impressoras de rede.', review: 'Confirme se o dispositivo é impressora esperada e segmentada.' },
  9200: { title: 'Elasticsearch', category: 'banco/busca', explanation: 'API HTTP comum do Elasticsearch.', review: 'Confirme se clientes da rede precisam acesso direto e revise exposição.' },
  27017: { title: 'MongoDB', category: 'banco', explanation: 'Banco MongoDB.', review: 'Confirme necessidade de acesso direto e segmentação.' },
};

export function explainPort(port: number, service = ''): PortKnowledge {
  const known = PORTS[port];
  if (known) return known;
  const serviceName = service && service !== 'unknown' ? service : 'serviço TCP';
  return {
    title: serviceName,
    category: 'outro',
    explanation: `O CloudOS observou ${serviceName} na porta ${port}.`,
    review: 'Confirme qual aplicação é dona da porta e se ela deveria estar acessível neste segmento.',
  };
}
