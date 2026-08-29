#include "native_shell_actions.h"

#include "native_app_launcher.h"

#include <shellapi.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <string>
#include <vector>

namespace CloudOS
{
namespace
{
std::wstring ToLower(std::wstring_view value)
{
    std::wstring result(value);
    std::transform(
        result.begin(),
        result.end(),
        result.begin(),
        [](wchar_t ch)
        {
            return static_cast<wchar_t>(std::towlower(ch));
        });
    return result;
}

std::vector<std::wstring> QueryTokens(std::wstring_view query)
{
    std::vector<std::wstring> tokens;
    std::wstring current;
    for (const wchar_t ch : query)
    {
        if (std::iswspace(ch))
        {
            if (!current.empty())
            {
                tokens.push_back(ToLower(current));
                current.clear();
            }
        }
        else
        {
            current.push_back(ch);
        }
    }
    if (!current.empty())
    {
        tokens.push_back(ToLower(current));
    }
    return tokens;
}

bool MatchesTokens(const ShellAction& action, const std::vector<std::wstring>& tokens)
{
    if (tokens.empty())
    {
        return true;
    }

    std::wstring haystack;
    haystack.reserve(512);
    for (const wchar_t* part : {
             action.id,
             action.title,
             action.description,
             action.keywords,
             action.target})
    {
        if (part != nullptr && part[0] != L'\0')
        {
            if (!haystack.empty())
            {
                haystack.push_back(L' ');
            }
            haystack += part;
        }
    }
    haystack = ToLower(haystack);

    for (const std::wstring& token : tokens)
    {
        if (haystack.find(token) == std::wstring::npos)
        {
            return false;
        }
    }
    return true;
}

bool LaunchTarget(
    HWND owner,
    const wchar_t* target,
    const wchar_t* parameters = nullptr)
{
    if (target == nullptr || target[0] == L'\0')
    {
        return false;
    }

    const HINSTANCE result = ShellExecuteW(
        owner,
        L"open",
        target,
        parameters != nullptr && parameters[0] != L'\0'
            ? parameters
            : nullptr,
        nullptr,
        SW_SHOWNORMAL);
    return reinterpret_cast<INT_PTR>(result) > 32;
}

bool RestartCloudOS(HWND owner)
{
    std::array<wchar_t, 32768> executable{};
    const DWORD length = GetModuleFileNameW(
        nullptr,
        executable.data(),
        static_cast<DWORD>(executable.size()));
    if (length == 0 || length >= executable.size())
    {
        return false;
    }

    if (!LaunchTarget(owner, executable.data()))
    {
        return false;
    }

    PostQuitMessage(0);
    return true;
}

bool ConfirmPowerAction(HWND owner, const ShellAction& action)
{
    std::wstring message = action.title;
    message += L"?\n\nEssa acao sera executada pelo Windows.";
    return MessageBoxW(
               owner,
               message.c_str(),
               L"CloudOS",
               MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) == IDYES;
}
} // namespace

const std::vector<ShellAction>& NativeShellActions::All()
{
    static const std::vector<ShellAction> actions{
        {L"cloud.browser", L"Navegador", L"Navegador in-process do CloudOS", L"navegador browser web internet google", L"browser", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.files", L"Arquivos", L"Arquivos Windows, CloudOS Drive e WSL", L"arquivos files explorer pastas documentos", L"files", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.projects", L"Projetos", L"Projetos persistentes do CloudOS", L"projetos desenvolvimento workspace", L"projects", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.terminal", L"Terminal", L"Terminal nativo via ConPTY", L"terminal cmd console prompt", L"terminal", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.wsl", L"WSL / Kali", L"Terminal Linux pela WSL", L"wsl kali linux bash", L"wsl", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.powershell", L"PowerShell", L"PowerShell via ConPTY", L"powershell terminal shell", L"powershell", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.drive", L"CloudOS Drive", L"Armazenamento isolado do CloudOS", L"drive armazenamento cloudos arquivos", L"drive", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.systemdrive", L"Disco do Sistema", L"Volume onde o Windows esta instalado", L"disco sistema windows volume", L"systemdrive", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.notepad", L"Bloco de Notas", L"Editor de texto nativo", L"notepad notas texto editor", L"notepad", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.calc", L"Calculadora", L"Calculadora nativa", L"calc calculadora matematica", L"calc", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.sysmon", L"Monitor do Sistema", L"CPU, RAM, disco e processos", L"monitor sistema cpu ram desempenho", L"sysmon", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.settings", L"Configuracoes CloudOS", L"Preferencias do shell", L"configuracoes settings cloudos preferencias", L"settings", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.apps", L"Aplicativos", L"Catalogo de aplicativos", L"apps aplicativos catalogo programas", L"apps", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.run", L"Executar", L"Executar comando ou aplicativo", L"executar run comando programa", L"run", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"cloud.health", L"Saude do Sistema", L"Diagnostico do runtime e WSL", L"saude diagnostico runtime wsl ambiente", L"health", L"", ShellActionCategory::CloudOS, ShellActionKind::CloudOSApp},
        {L"settings.display", L"Tela", L"Resolucao, escala e monitores", L"display tela resolucao escala monitor", L"ms-settings:display", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.advanced-display", L"Tela avancada", L"Taxa de atualizacao e propriedades", L"display avancado hz taxa atualizacao", L"ms-settings:display-advanced", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.sound", L"Som", L"Saida, entrada e dispositivos de audio", L"som audio speaker microfone", L"ms-settings:sound", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.volume", L"Mixer de volume", L"Volume por aplicativo", L"volume mixer audio aplicativo", L"ms-settings:apps-volume", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.power", L"Energia", L"Energia e suspensao", L"energia bateria suspensao power", L"ms-settings:powersleep", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.energy", L"Recomendacoes de energia", L"Sugestoes de eficiencia energetica", L"energia eficiencia recomendacoes", L"ms-settings:energyrecommendations", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.storage", L"Armazenamento", L"Uso de disco e gerenciamento de armazenamento", L"storage armazenamento disco espaco", L"ms-settings:storagesense", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.storage-policies", L"Sensor de Armazenamento", L"Limpeza automatica do armazenamento", L"storage sense limpeza temporarios", L"ms-settings:storagepolicies", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.disks-volumes", L"Discos e volumes", L"Gerenciar discos e volumes modernos", L"discos volumes particoes storage", L"ms-settings:disksandvolumes", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.notifications", L"Notificacoes", L"Preferencias de notificacao", L"notificacoes alertas banner", L"ms-settings:notifications", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.focus", L"Assistente de foco", L"Regras de foco e nao perturbe", L"foco focus quiet hours nao perturbe", L"ms-settings:quiethours", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.clipboard", L"Area de transferencia", L"Historico e sincronizacao", L"clipboard area transferencia copiar colar", L"ms-settings:clipboard", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.multitasking", L"Multitarefa", L"Snap e comportamento de janelas", L"multitarefa snap janelas desktop", L"ms-settings:multitasking", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.nightlight", L"Luz noturna", L"Temperatura de cor da tela", L"luz noturna night light display", L"ms-settings:nightlight", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.graphics", L"Graficos", L"Preferencias de GPU por aplicativo", L"gpu graficos graphics desempenho", L"ms-settings:display-advancedgraphics", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.remote-desktop", L"Area de Trabalho Remota", L"Configuracoes de Remote Desktop", L"remote desktop rdp remoto", L"ms-settings:remotedesktop", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.about", L"Sobre o Windows", L"Informacoes do dispositivo e sistema", L"sobre windows hardware versao", L"ms-settings:about", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.recovery", L"Recuperacao", L"Opcoes de recuperacao do Windows", L"recuperacao recovery reset restaurar", L"ms-settings:recovery", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.activation", L"Ativacao", L"Estado de ativacao do Windows", L"ativacao licenca windows", L"ms-settings:activation", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.update", L"Windows Update", L"Atualizacoes do sistema", L"windows update atualizacao patch", L"ms-settings:windowsupdate", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.update-options", L"Windows Update avancado", L"Opcoes avancadas de atualizacao", L"update avancado windows", L"ms-settings:windowsupdate-options", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.security", L"Seguranca do Windows", L"Configuracoes de seguranca", L"defender seguranca antivirus firewall", L"ms-settings:windowsdefender", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.optional", L"Recursos opcionais", L"Gerenciar recursos opcionais", L"recursos opcionais features windows", L"ms-settings:optionalfeatures", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.developers", L"Para desenvolvedores", L"Configuracoes de desenvolvimento", L"desenvolvedor developer dev mode", L"ms-settings:developers", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.troubleshoot", L"Solucao de problemas", L"Ferramentas de diagnostico do Windows", L"troubleshoot problemas diagnostico", L"ms-settings:troubleshoot", L"", ShellActionCategory::System, ShellActionKind::SettingsUri},
        {L"settings.network", L"Rede e Internet", L"Estado e configuracoes de rede", L"rede internet network status", L"ms-settings:network-status", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.network-advanced", L"Rede avancada", L"Adaptadores e configuracoes avancadas", L"rede advanced adapters network", L"ms-settings:network-advancedsettings", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.wifi", L"Wi-Fi", L"Redes Wi-Fi", L"wifi wireless rede sem fio", L"ms-settings:network-wifi", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.known-wifi", L"Redes conhecidas", L"Gerenciar redes Wi-Fi conhecidas", L"wifi redes conhecidas senha", L"ms-settings:network-wifisettings", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.ethernet", L"Ethernet", L"Configuracoes Ethernet", L"ethernet cabo rede lan", L"ms-settings:network-ethernet", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.vpn", L"VPN", L"Conexoes VPN", L"vpn tunel rede", L"ms-settings:network-vpn", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.proxy", L"Proxy", L"Configuracoes de proxy", L"proxy internet rede", L"ms-settings:network-proxy", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.hotspot", L"Hotspot movel", L"Compartilhamento de conexao", L"hotspot tethering compartilhar internet", L"ms-settings:network-mobilehotspot", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.airplane", L"Modo aviao", L"Radios e modo aviao", L"modo aviao airplane radio", L"ms-settings:network-airplanemode", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.bluetooth", L"Bluetooth", L"Bluetooth e dispositivos", L"bluetooth dispositivos pairing", L"ms-settings:bluetooth", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.printers", L"Impressoras", L"Impressoras e scanners", L"impressora scanner printer", L"ms-settings:printers", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.usb", L"USB", L"Preferencias de dispositivos USB", L"usb dispositivo hardware", L"ms-settings:usb", L"", ShellActionCategory::Network, ShellActionKind::SettingsUri},
        {L"settings.personalization", L"Personalizacao", L"Pagina principal de personalizacao", L"personalizacao tema aparencia", L"ms-settings:personalization", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.background", L"Plano de fundo", L"Wallpaper do Windows", L"wallpaper fundo background", L"ms-settings:personalization-background", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.colors", L"Cores", L"Tema claro/escuro e cor de destaque", L"cores tema dark light accent", L"ms-settings:personalization-colors", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.themes", L"Temas", L"Temas instalados", L"temas themes aparencia", L"ms-settings:themes", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.fonts", L"Fontes", L"Fontes instaladas", L"fontes fonts tipografia", L"ms-settings:fonts", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.lockscreen", L"Tela de bloqueio", L"Personalizar tela de bloqueio", L"lockscreen bloqueio wallpaper", L"ms-settings:lockscreen", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.start", L"Menu Iniciar do Windows", L"Preferencias do Start do Windows", L"start iniciar windows menu", L"ms-settings:personalization-start", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.start-places", L"Pastas no Menu Iniciar", L"Escolher pastas mostradas no Start", L"start pastas places iniciar", L"ms-settings:personalization-start-places", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.taskbar", L"Barra de tarefas do Windows", L"Preferencias da taskbar do Windows", L"taskbar barra tarefas windows", L"ms-settings:taskbar", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.touchkbd", L"Teclado virtual", L"Personalizar teclado virtual", L"teclado virtual touch keyboard", L"ms-settings:personalization-touchkeyboard", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.typing", L"Digitacao", L"Sugestoes e preferencias de digitacao", L"typing digitacao teclado sugestoes", L"ms-settings:typing", L"", ShellActionCategory::Personalization, ShellActionKind::SettingsUri},
        {L"settings.privacy", L"Privacidade", L"Painel geral de privacidade", L"privacidade privacy permissoes", L"ms-settings:privacy", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.camera-privacy", L"Privacidade da camera", L"Permissoes de camera", L"camera webcam privacidade permissoes", L"ms-settings:privacy-webcam", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.microphone-privacy", L"Privacidade do microfone", L"Permissoes de microfone", L"microfone privacy audio permissoes", L"ms-settings:privacy-microphone", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.location-privacy", L"Privacidade de localizacao", L"Permissoes de localizacao", L"localizacao gps privacy permissoes", L"ms-settings:privacy-location", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.filesystem-privacy", L"Privacidade do sistema de arquivos", L"Acesso de apps ao sistema de arquivos", L"arquivos privacidade permissoes filesystem", L"ms-settings:privacy-broadfilesystemaccess", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.speech-privacy", L"Privacidade de fala", L"Fala e digitacao online", L"speech fala voz privacidade", L"ms-settings:privacy-speech", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.access-display", L"Acessibilidade visual", L"Tela e tamanho de texto", L"acessibilidade display texto", L"ms-settings:easeofaccess-display", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.access-keyboard", L"Acessibilidade do teclado", L"Teclas de aderencia e acessibilidade", L"acessibilidade teclado keyboard", L"ms-settings:easeofaccess-keyboard", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.access-mouse", L"Acessibilidade do mouse", L"Ponteiro e controle do mouse", L"acessibilidade mouse ponteiro", L"ms-settings:easeofaccess-mouse", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.access-narrator", L"Narrador", L"Leitor de tela do Windows", L"narrador narrator acessibilidade", L"ms-settings:easeofaccess-narrator", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.access-magnifier", L"Lupa", L"Ampliacao da tela", L"lupa magnifier zoom acessibilidade", L"ms-settings:easeofaccess-magnifier", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.search", L"Pesquisa do Windows", L"Configuracoes de pesquisa", L"pesquisa search windows indexacao", L"ms-settings:search", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.search-permissions", L"Permissoes de pesquisa", L"Conteudo e permissoes de pesquisa", L"pesquisa permissoes search", L"ms-settings:search-permissions", L"", ShellActionCategory::Privacy, ShellActionKind::SettingsUri},
        {L"settings.apps", L"Aplicativos instalados", L"Gerenciar aplicativos instalados", L"apps aplicativos instalados desinstalar", L"ms-settings:appsfeatures", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.default-apps", L"Aplicativos padrao", L"Escolher aplicativos padrao", L"default apps padrao associacoes", L"ms-settings:defaultapps", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.startup-apps", L"Aplicativos de inicializacao", L"Apps executados no logon", L"startup inicializacao apps logon", L"ms-settings:startupapps", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.video", L"Reproducao de video", L"Preferencias de video", L"video playback hdr streaming", L"ms-settings:videoplayback", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.accounts", L"Suas informacoes", L"Informacoes da conta", L"conta usuario account perfil", L"ms-settings:yourinfo", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.signin", L"Opcoes de entrada", L"Windows Hello e entrada", L"signin login hello pin senha", L"ms-settings:signinoptions", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.workplace", L"Trabalho ou escola", L"Contas corporativas e escolares", L"workplace escola trabalho conta", L"ms-settings:workplace", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.date", L"Data e hora", L"Relogio, fuso e sincronizacao", L"data hora timezone relogio", L"ms-settings:dateandtime", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.language", L"Idioma e regiao", L"Idioma, formato e regiao", L"idioma regiao language keyboard", L"ms-settings:regionlanguage", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.gamemode", L"Modo de Jogo", L"Preferencias do Game Mode", L"game mode jogo gaming desempenho", L"ms-settings:gaming-gamemode", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"settings.gamebar", L"Game Bar", L"Atalhos e recursos de jogo", L"game bar xbox captura gaming", L"ms-settings:gaming-gamebar", L"", ShellActionCategory::Apps, ShellActionKind::SettingsUri},
        {L"classic.taskmgr", L"Gerenciador de Tarefas", L"Processos, desempenho e inicializacao", L"taskmgr tarefas processos desempenho", L"taskmgr.exe", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.device", L"Gerenciador de Dispositivos", L"Hardware e drivers", L"dispositivos device manager drivers", L"devmgmt.msc", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.services", L"Servicos", L"Servicos do Windows", L"services servicos windows", L"services.msc", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.eventviewer", L"Visualizador de Eventos", L"Logs e eventos do Windows", L"event viewer logs eventos", L"eventvwr.msc", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.diskmgmt", L"Gerenciamento de Disco", L"Particoes e volumes", L"disk management particoes volumes", L"diskmgmt.msc", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.compmgmt", L"Gerenciamento do Computador", L"Console administrativo", L"computer management administracao", L"compmgmt.msc", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.msinfo", L"Informacoes do Sistema", L"Detalhes de hardware e sistema", L"msinfo hardware sistema info", L"msinfo32.exe", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.control", L"Painel de Controle", L"Painel de Controle classico", L"control panel painel controle", L"control.exe", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.programs", L"Programas e Recursos", L"Desinstalar programas classicos", L"appwiz programas recursos desinstalar", L"appwiz.cpl", L"", ShellActionCategory::Apps, ShellActionKind::ShellTarget},
        {L"classic.adapters", L"Adaptadores de Rede", L"Conexoes de rede classicas", L"ncpa adaptadores rede conexoes", L"ncpa.cpl", L"", ShellActionCategory::Network, ShellActionKind::ShellTarget},
        {L"classic.powercfg", L"Opcoes de Energia", L"Planos de energia classicos", L"power energia planos bateria", L"powercfg.cpl", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.sysprops", L"Propriedades do Sistema", L"Configuracoes avancadas do sistema", L"system properties sysdm avancado", L"sysdm.cpl", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"classic.cleanmgr", L"Limpeza de Disco", L"Limpeza de arquivos temporarios", L"cleanmgr limpeza disco temporarios", L"cleanmgr.exe", L"", ShellActionCategory::System, ShellActionKind::ShellTarget},
        {L"session.lock", L"Bloquear", L"Bloquear a estacao de trabalho", L"lock bloquear sessao", L"", L"", ShellActionCategory::Session, ShellActionKind::Lock},
        {L"session.restart-cloudos", L"Reiniciar CloudOS", L"Reiniciar apenas o shell CloudOS", L"reiniciar restart cloudos shell", L"", L"", ShellActionCategory::Session, ShellActionKind::RestartCloudOS},
        {L"session.exit-cloudos", L"Sair do CloudOS", L"Encerrar o shell CloudOS", L"sair exit cloudos shell", L"", L"", ShellActionCategory::Session, ShellActionKind::ExitCloudOS},
        {L"session.signout", L"Sair do Windows", L"Encerrar a sessao do Windows", L"signout logoff sair windows", L"shutdown.exe", L"/l", ShellActionCategory::Session, ShellActionKind::PowerCommand},
        {L"session.restart-windows", L"Reiniciar Windows", L"Reiniciar o computador", L"restart reboot reiniciar windows", L"shutdown.exe", L"/r /t 0", ShellActionCategory::Session, ShellActionKind::PowerCommand},
        {L"session.shutdown", L"Desligar Windows", L"Desligar o computador", L"shutdown desligar windows power", L"shutdown.exe", L"/s /t 0", ShellActionCategory::Session, ShellActionKind::PowerCommand},
    };
    return actions;
}

const ShellAction* NativeShellActions::Find(std::wstring_view id) noexcept
{
    const auto& actions = All();
    const auto it = std::find_if(
        actions.begin(),
        actions.end(),
        [id](const ShellAction& action)
        {
            return id == action.id;
        });
    return it == actions.end() ? nullptr : &(*it);
}

std::vector<std::size_t> NativeShellActions::Filter(
    std::wstring_view query,
    ShellActionCategory category)
{
    const auto tokens = QueryTokens(query);
    const auto& actions = All();
    std::vector<std::size_t> result;
    result.reserve(actions.size());

    for (std::size_t index = 0; index < actions.size(); ++index)
    {
        const ShellAction& action = actions[index];
        if (category != ShellActionCategory::All &&
            action.category != category)
        {
            continue;
        }
        if (MatchesTokens(action, tokens))
        {
            result.push_back(index);
        }
    }
    return result;
}

bool NativeShellActions::Execute(
    HINSTANCE instance,
    HWND owner,
    const ShellAction& action)
{
    switch (action.kind)
    {
    case ShellActionKind::CloudOSApp:
        NativeAppLauncher::LaunchById(
            instance,
            owner,
            action.target != nullptr ? action.target : L"");
        return true;

    case ShellActionKind::SettingsUri:
    case ShellActionKind::ShellTarget:
        return LaunchTarget(owner, action.target, action.parameters);

    case ShellActionKind::Lock:
        return LockWorkStation() != FALSE;

    case ShellActionKind::RestartCloudOS:
        return RestartCloudOS(owner);

    case ShellActionKind::ExitCloudOS:
        PostQuitMessage(0);
        return true;

    case ShellActionKind::PowerCommand:
        if (!ConfirmPowerAction(owner, action))
        {
            return false;
        }
        return LaunchTarget(owner, action.target, action.parameters);

    default:
        return false;
    }
}

const wchar_t* NativeShellActions::CategoryLabel(
    ShellActionCategory category) noexcept
{
    switch (category)
    {
    case ShellActionCategory::All:
        return L"Todos";
    case ShellActionCategory::CloudOS:
        return L"CloudOS";
    case ShellActionCategory::System:
        return L"Sistema";
    case ShellActionCategory::Network:
        return L"Rede";
    case ShellActionCategory::Personalization:
        return L"Personalizacao";
    case ShellActionCategory::Privacy:
        return L"Privacidade";
    case ShellActionCategory::Apps:
        return L"Apps e contas";
    case ShellActionCategory::Session:
        return L"Sessao";
    default:
        return L"Todos";
    }
}
} // namespace CloudOS
