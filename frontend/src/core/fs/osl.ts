export const oslScripts: [string, string, string, string][] = [
  [
    'C:\\Users\\user\\Documents\\welcome.osl',
    'welcome.osl',
    'C:\\Users\\user\\Documents',
    `
// Welcome to Obsidian Script Language (OSL)
let name = "Developer";
system::log("Iniciando script de boas-vindas...");

fn say_hello(user) {
    system::log("Olá, " + user + "! Bem-vindo ao ObsidianOS nativo.");
}

say_hello(name);

let ram = system::get_resource("ram");
system::log("RAM atual em uso: " + ram + "MB");

if (ram > 500) {
    system::log("O sistema está rodando processos pesados.");
} else {
    system::log("O sistema está saudável.");
}
    `
  ]
];

