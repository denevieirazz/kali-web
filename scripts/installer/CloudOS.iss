; Script Inno Setup 6/7 para o Instalador Oficial do CloudOS V21
; Suporta instalacao per-user (sem UAC) ou per-machine, verificacao de dependencias, atalhos e desinstalacao limpa.

#define MyAppName "CloudOS"
#define MyAppVersion "21.0.0-rc.1.3"
#define MyAppPublisher "CloudOS"
#define MyAppExeName "CloudOS.exe"
#define MyAppSourcePath "..\..\dist\CloudOS"

[Setup]
AppId={{D95E3F81-9876-4C2E-82C3-5A3E22915F77}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\CloudOS
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist\releases\21.0.0-rc.1.3
OutputBaseFilename=CloudOS-Setup-21.0.0-rc.1.3-x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
CloseApplications=yes
CloseApplicationsFilter=*.exe

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourcePath}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Verificacao de dependencias do sistema
function IsVcRedistInstalled: Boolean;
begin
  Result := RegKeyExists(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64') or
            RegKeyExists(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64');
end;

function IsWebView2Installed: Boolean;
begin
  Result := RegKeyExists(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
            RegKeyExists(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') or
            DirExists('C:\Program Files (x86)\Microsoft\EdgeWebView\Application');
end;

function IsWslInstalled: Boolean;
begin
  Result := FileExists(ExpandConstant('{win}\System32\wsl.exe'));
end;

function InitializeSetup: Boolean;
var
  WarnMsg: String;
begin
  Result := True;
  WarnMsg := '';

  if not IsVcRedistInstalled then
  begin
    WarnMsg := WarnMsg + '- Visual C++ 2015-2022 Redistributable (x64) nao detectado.' + #13#10;
  end;

  if not IsWebView2Installed then
  begin
    WarnMsg := WarnMsg + '- Microsoft Edge WebView2 Runtime nao detectado (necessario para o Navegador).' + #13#10;
  end;

  if not IsWslInstalled then
  begin
    // WSL e opcional: apenas avisa, nao bloqueia
    WarnMsg := WarnMsg + '- Subsistema WSL2 nao detectado (recursos Linux ficarao indisponiveis, mas o CloudOS funcionara normalmente no modo Windows).' + #13#10;
  end;

  if WarnMsg <> '' then
  begin
    MsgBox('Avisos de compatibilidade do CloudOS:' + #13#10#13#10 + WarnMsg + #13#10 +
           'A instalacao continuara normalmente.', mbInformation, MB_OK);
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  SelectedDir: String;
  WinDir: String;
  SysDir: String;
  TempDir: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    SelectedDir := Uppercase(RemoveBackslashUnlessRoot(WizardDirValue));
    WinDir := Uppercase(RemoveBackslashUnlessRoot(ExpandConstant('{win}')));
    SysDir := Uppercase(RemoveBackslashUnlessRoot(ExpandConstant('{sys}')));
    TempDir := Uppercase(RemoveBackslashUnlessRoot(ExpandConstant('{tmp}')));

    // Bloquear raiz de volume (ex: C:, C:\)
    if (Length(SelectedDir) <= 3) and (Pos(':', SelectedDir) = 2) then
    begin
      MsgBox('O CloudOS nao pode ser instalado diretamente na raiz do disco. Escolha uma subpasta valida.', mbError, MB_OK);
      Result := False;
      Exit;
    end;

    // Bloquear pasta do Windows e System32
    if (Pos(WinDir, SelectedDir) = 1) or (Pos(SysDir, SelectedDir) = 1) then
    begin
      MsgBox('O CloudOS nao pode ser instalado dentro do diretorio do Windows. Escolha outro diretorio.', mbError, MB_OK);
      Result := False;
      Exit;
    end;

    // Bloquear diretorio temporario
    if Pos(TempDir, SelectedDir) = 1 then
    begin
      MsgBox('O CloudOS nao pode ser instalado em uma pasta temporaria. Escolha um diretorio definitivo.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;
