; Instalador do Bergastream para Windows (Inno Setup 6).
;
; Instala só para o usuário, sem pedir administrador, em
; %LOCALAPPDATA%\Programs\Bergastream, com atalho no menu Iniciar e entrada em
; "Adicionar ou remover programas". O próprio app baixa a versão nova e roda
; este instalador em silêncio (/VERYSILENT): ele fecha o app, troca os
; arquivos e abre o app de novo ([Run], que também vale no modo silencioso).
;
; Gerado pelo CI (.github/workflows/release.yml):
;   iscc /DAppVersion=0.8.4 /DSourceDir=<build\windows\x64\runner\Release> bergastream.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Nunca troque o AppId: é por ele que o Windows reconhece o app instalado.
AppId={{A1E50D98-A1AA-4427-B902-ED2C72FB6C6B}
AppName=Bergastream
AppVersion={#AppVersion}
AppVerName=Bergastream {#AppVersion}
AppPublisher=Bergastream
AppPublisherURL=https://github.com/Agelinena/bergastream
AppUpdatesURL=https://github.com/Agelinena/bergastream/releases
DefaultDirName={localappdata}\Programs\Bergastream
DefaultGroupName=Bergastream
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Fecha o app aberto (Gerenciador de Reinicialização) antes de trocar os
; arquivos; quem abre de novo é o [Run].
CloseApplications=force
RestartApplications=no
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bergastream.exe
UninstallDisplayName=Bergastream
OutputDir=..\..\dist
OutputBaseFilename=bergastream-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Arquivos de uma versão anterior que a nova não tem mais.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Bergastream"; Filename: "{app}\bergastream.exe"
Name: "{autodesktop}\Bergastream"; Filename: "{app}\bergastream.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\bergastream.exe"; Description: "{cm:LaunchProgram,Bergastream}"; Flags: nowait postinstall
