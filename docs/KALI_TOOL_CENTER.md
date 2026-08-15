# Kali Tool Center

Branch: `feature/cloudos-kali-tool-center`

O Kali Tool Center é uma central de inventário e acesso às ferramentas instaladas em uma distribuição WSL. Ele não cria uma API de execução arbitrária e não substitui as fronteiras de segurança já existentes do CloudOS.

## Inventário

O backend mantém uma allowlist versionada de ferramentas conhecidas. A detecção usa um script fixo do servidor com `command -v` e argumentos também fixos do manifesto. O frontend pode escolher apenas uma distribuição que o backend valida como instalada.

A resposta pública contém somente:

- ID estável do manifesto;
- comando/nome canônico da ferramenta;
- categoria;
- descrição;
- aliases de GUI;
- booleano `installed`.

Não são retornados caminho do executável, argv, shell, ambiente, comando construído ou qualquer segredo.

## Execução

O Tool Center **não** possui endpoints `/execute`, `/run`, `/command` ou equivalentes.

- CLI: o usuário abre o CloudOS Terminal autenticado no perfil WSL e opera a sessão existente. O Tool Center pode copiar somente o nome fixo da ferramenta para a área de transferência; não injeta comandos automaticamente.
- GUI: quando uma aplicação WSLg correspondente existe no catálogo já produzido pelo backend, a abertura usa `POST /api/apps/:opaqueId/launch`. O frontend continua sem enviar executável/path/argv.

As verificações de autorização/escopo de uma execução real continuam pertencendo às camadas de terminal, projeto e ferramentas específicas; o workspace visual desta feature não deve ser tratado como substituto de autorização técnica no backend.

## Workspace de escopo

O painel persiste localmente apenas:

```json
{
  "projectName": "Projeto autorizado",
  "notes": "...",
  "scopes": ["example.com", "10.0.0.0/24"],
  "activeScope": "example.com"
}
```

Aceitos:

- hostname/domínio;
- IPv4;
- CIDR IPv4;
- URL HTTP/HTTPS sem userinfo.

Valores com controles, espaços, esquema perigoso, IPv4/CIDR inválido ou credenciais embutidas são rejeitados. Máximo de 50 ativos; duplicatas são normalizadas/removidas.

Este estado não contém JWT, credencial, comando, resultado de scanner ou evidência.

## Ferramentas catalogadas

A primeira versão inclui categorias Recon, OSINT, Web, Rede, Credenciais, Frameworks, Wireless, Forense e Reverse, com ferramentas como Nmap, Masscan, Amass, theHarvester, Nikto, Gobuster, sqlmap, Burp Suite, Hydra, John, Hashcat, Metasploit, Wireshark, Aircrack-ng, Binwalk, Autopsy e Ghidra.

A presença no manifesto não significa instalação nem execução automática. A UI mostra claramente `instalada`/`ausente` segundo a distribuição consultada.

## Testes

Backend:

- IDs/comandos fixos e únicos;
- parser ignora comandos que não estejam no manifesto;
- resposta pública não contém path/argv/executable.

Frontend:

- normalização de domínio/IP/CIDR/URL;
- rejeição de valores inseguros;
- remoção de campos desconhecidos;
- limite e deduplicação de escopo;
- manutenção de `activeScope` válido;
- contrato estático impede endpoint de comando arbitrário;
- GUI usa somente `app.id` opaco.

## Limitações

- esta feature inventaria ferramentas; não instala pacotes Kali automaticamente;
- não executa scanners em lote nem cria campanhas automáticas;
- o Kali/WSL precisa estar instalado e operacional para inventário real;
- algumas ferramentas GUI podem existir mas não ser correlacionadas se o nome no `.desktop` for muito diferente do alias conhecido;
- Evidence Vault, Findings e Report Builder devem ser integrados numa fase posterior, sem transformar este painel em uma rota de execução arbitrária.
