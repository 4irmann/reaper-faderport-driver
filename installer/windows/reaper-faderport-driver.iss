; 4irmann's FaderPort Driver for REAPER - Windows installer (Inno Setup 6)
;
; Build (after building the C++ extension, DllPath absolute or relative to this file):
;   iscc /DAppVersion=2.0.0 installer\windows\reaper-faderport-driver.iss
;
; Installs into the REAPER resource path (default %APPDATA%\REAPER, portable installs selectable):
;   UserPlugins\reaper_4irmann_faderport.dll      C++ extension
;   Scripts\reaper-faderport-driver\...            Lua driver, helper actions, emulator
; Lua actions are registered on the next REAPER start via the ReaScript API
; (Scripts\__startup.lua -> register_actions.lua), so reaper-kb.ini is only touched on uninstall.

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#ifndef DllPath
  #define DllPath "..\..\cpp\build\Release\reaper_4irmann_faderport.dll"
#endif

#define AppName "4irmann's FaderPort Driver for REAPER"
#define ScriptDir "reaper-faderport-driver"
#define StartupBegin "-- BEGIN reaper-faderport-driver (managed by installer)"
#define StartupEnd "-- END reaper-faderport-driver"

[Setup]
AppId={{7E0C8E1A-3F2B-4C51-9A57-1F3B8C2D6E40}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=4irmann
AppPublisherURL=https://github.com/4irmann/reaper-faderport-driver
AppSupportURL=https://github.com/4irmann/reaper-faderport-driver/issues
DefaultDirName={userappdata}\REAPER
DirExistsWarning=no
AppendDefaultDirName=no
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=reaper-faderport-driver-{#AppVersion}-setup
LicenseFile=..\..\LICENSE
UninstallFilesDir={app}\Data\reaper-faderport-driver
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
ShowLanguageDialog=auto

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Messages]
en.SelectDirLabel3=Setup will install the driver into the following REAPER resource path (REAPER: Options > Show REAPER resource path in explorer/finder).
de.SelectDirLabel3=Der Treiber wird in den folgenden REAPER-Ressourcenpfad installiert (REAPER: Options > Show REAPER resource path in explorer/finder).
en.SelectDirBrowseLabel=For a portable REAPER installation select its folder, then click Next.
de.SelectDirBrowseLabel=Bei einer portablen REAPER-Installation deren Ordner auswählen und auf Weiter klicken.

[CustomMessages]
en.TypeCpp=C++ extension (recommended)
de.TypeCpp=C++-Extension (empfohlen)
en.TypeLua=Lua ReaScript
de.TypeLua=Lua-ReaScript
en.TypeFull=Both variants
de.TypeFull=Beide Varianten
en.TypeCustom=Custom
de.TypeCustom=Benutzerdefiniert
en.CompCpp=C++ extension (native control surface)
de.CompCpp=C++-Extension (native Control Surface)
en.CompEmulator=Emulator window for the C++ extension
de.CompEmulator=Emulator-Fenster für die C++-Extension
en.CompLua=Lua driver incl. emulator and helper actions
de.CompLua=Lua-Treiber inkl. Emulator und Hilfs-Actions
en.TaskAutostart=Start the Lua driver automatically with REAPER
de.TaskAutostart=Lua-Treiber automatisch mit REAPER starten
en.TaskGroup=Lua driver:
de.TaskGroup=Lua-Treiber:
en.ReaperRunning=REAPER is running. Please close REAPER and click Retry.
de.ReaperRunning=REAPER läuft. Bitte REAPER schließen und auf Wiederholen klicken.
en.NoReaperIni=The selected folder doesn't contain reaper.ini, so it doesn't look like a REAPER resource path.%n%nInstall anyway?
de.NoReaperIni=Der gewählte Ordner enthält keine reaper.ini und sieht nicht wie ein REAPER-Ressourcenpfad aus.%n%nTrotzdem installieren?
en.BothInstalled=Both variants are installed. Only one can run at a time: the C++ extension is active by default. To use the Lua driver, disable the C++ driver with the action "4irmann FaderPort (C++): Enable/disable driver".
de.BothInstalled=Beide Varianten sind installiert. Es kann immer nur eine laufen: Standardmäßig ist die C++-Extension aktiv. Für den Lua-Treiber die C++-Variante mit der Action "4irmann FaderPort (C++): Enable/disable driver" deaktivieren.
en.StartReaper=Start REAPER
de.StartReaper=REAPER starten

[Types]
Name: "cpp"; Description: "{cm:TypeCpp}"
Name: "lua"; Description: "{cm:TypeLua}"
Name: "full"; Description: "{cm:TypeFull}"
Name: "custom"; Description: "{cm:TypeCustom}"; Flags: iscustom

[Components]
Name: "cpp"; Description: "{cm:CompCpp}"; Types: cpp full
Name: "emulator"; Description: "{cm:CompEmulator}"; Types: cpp full
Name: "lua"; Description: "{cm:CompLua}"; Types: lua full

[Tasks]
Name: "autostart"; Description: "{cm:TaskAutostart}"; GroupDescription: "{cm:TaskGroup}"; Components: lua; Flags: unchecked

[Files]
Source: "{#DllPath}"; DestDir: "{app}\UserPlugins"; Components: cpp; Flags: ignoreversion
Source: "..\..\lua\*.lua"; DestDir: "{app}\Scripts\{#ScriptDir}"; Components: lua emulator; Flags: ignoreversion
Source: "..\..\lua\faderport\*.lua"; DestDir: "{app}\Scripts\{#ScriptDir}\faderport"; Components: lua emulator; Flags: ignoreversion
Source: "..\..\lua\README.md"; DestDir: "{app}\Scripts\{#ScriptDir}"; DestName: "README-lua.md"; Components: lua emulator; Flags: ignoreversion
Source: "..\..\cpp\README.md"; DestDir: "{app}\Scripts\{#ScriptDir}"; DestName: "README-cpp.md"; Components: cpp; Flags: ignoreversion
Source: "..\..\cpp\4irmann_faderport_bindings.txt"; DestDir: "{app}\Scripts\{#ScriptDir}"; DestName: "4irmann_faderport_bindings.txt.example"; Components: cpp; Flags: ignoreversion
Source: "..\..\LICENSE"; DestDir: "{app}\Scripts\{#ScriptDir}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\..\NOTICE"; DestDir: "{app}\Scripts\{#ScriptDir}"; DestName: "NOTICE.txt"; Flags: ignoreversion
Source: "register_actions.lua"; DestDir: "{app}\Scripts\{#ScriptDir}"; Components: lua emulator; Flags: ignoreversion

[InstallDelete]
; files of versions before the rename "Airmann" -> "4irmann": two extensions would open the FaderPort
Type: files; Name: "{app}\UserPlugins\reaper_airmann_faderport.dll"
Type: files; Name: "{app}\Scripts\{#ScriptDir}\Airmann_FaderPort*.lua"
Type: files; Name: "{app}\Scripts\{#ScriptDir}\airmann_faderport_bindings.txt.example"

[Run]
Filename: "{code:ReaperExe}"; Description: "{cm:StartReaper}"; Flags: postinstall nowait skipifsilent; Check: ReaperExeExists

[Code]
const
  MANAGED_DIR = '{#ScriptDir}';

function ScriptsDir: String;
begin
  Result := ExpandConstant('{app}\Scripts\');
end;

function IsReaperRunning: Boolean;
begin
  Result := FindWindowByClassName('REAPERwnd') <> 0;
end;

function WaitForReaperClosed: Boolean;
begin
  Result := True;
  while IsReaperRunning do
  begin
    if MsgBox(CustomMessage('ReaperRunning'), mbError, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function ReaperExe(Param: String): String;
begin
  // portable installation: reaper.exe next to reaper.ini
  if FileExists(ExpandConstant('{app}\reaper.exe')) then
    Result := ExpandConstant('{app}\reaper.exe')
  else
    Result := ExpandConstant('{commonpf64}\REAPER (x64)\reaper.exe');
end;

function ReaperExeExists: Boolean;
begin
  Result := FileExists(ReaperExe(''));
end;

//------------------------------------------------- register_actions.txt
// read by register_actions.lua on REAPER start (via __startup.lua)

procedure WriteActionList;
var
  Lines: TArrayOfString;
  n: Integer;
begin
  SetArrayLength(Lines, 8);
  n := 0;
  Lines[n] := '# written by the installer: scripts registered as actions on REAPER start';
  n := n + 1;
  if WizardIsComponentSelected('lua') then
  begin
    Lines[n] := '4irmann_FaderPort.lua';
    Lines[n + 1] := '4irmann_FaderPort - Toggle emulator.lua';
    Lines[n + 2] := '4irmann_FaderPort - Reset.lua';
    Lines[n + 3] := '4irmann_FaderPort - Show FX parameters.lua';
    Lines[n + 4] := '4irmann_FaderPort - Toggle MIDI dump.lua';
    n := n + 5;
  end;
  if WizardIsComponentSelected('emulator') then
  begin
    Lines[n] := '4irmann_FaderPort - C++ emulator.lua';
    n := n + 1;
  end;
  if WizardIsTaskSelected('autostart') then
  begin
    Lines[n] := 'autostart';
    n := n + 1;
  end;
  SetArrayLength(Lines, n);
  SaveStringsToFile(ScriptsDir + MANAGED_DIR + '\register_actions.txt', Lines, False);
end;

//---------------------------------------------------------- __startup.lua
// the managed block is plain ASCII, the rest of the file is passed through unchanged

procedure UpdateStartup(Enable: Boolean);
var
  StartupFile: String;
  Lines, Output: TArrayOfString;
  i, n: Integer;
  Skip: Boolean;
begin
  StartupFile := ScriptsDir + '__startup.lua';
  if not LoadStringsFromFile(StartupFile, Lines) then
  begin
    if not Enable then
      Exit;
    SetArrayLength(Lines, 0);
  end;

  n := 0;
  Skip := False;
  SetArrayLength(Output, GetArrayLength(Lines) + 3);
  for i := 0 to GetArrayLength(Lines) - 1 do
  begin
    if Lines[i] = '{#StartupBegin}' then
      Skip := True
    else if Skip and (Lines[i] = '{#StartupEnd}') then
      Skip := False
    else if not Skip then
    begin
      Output[n] := Lines[i];
      n := n + 1;
    end;
  end;

  if Enable then
  begin
    Output[n] := '{#StartupBegin}';
    Output[n + 1] := 'dofile(reaper.GetResourcePath() .. "/Scripts/{#ScriptDir}/register_actions.lua")';
    Output[n + 2] := '{#StartupEnd}';
    n := n + 3;
  end;

  SetArrayLength(Output, n);
  SaveStringsToFile(StartupFile, Output, False);
end;

//------------------------------------------------------------ reaper-kb.ini
// uninstall only: remove the actions of our scripts (lines are passed through byte by byte)

procedure RemoveRegisteredActions;
var
  KbFile: String;
  Lines, Output: TArrayOfString;
  i, n: Integer;
begin
  KbFile := ExpandConstant('{app}\reaper-kb.ini');
  if not LoadStringsFromFile(KbFile, Lines) then
    Exit;
  n := 0;
  SetArrayLength(Output, GetArrayLength(Lines));
  for i := 0 to GetArrayLength(Lines) - 1 do
    if not ((Pos('SCR ', Lines[i]) = 1) and (Pos(MANAGED_DIR, Lines[i]) > 0)) then
    begin
      Output[n] := Lines[i];
      n := n + 1;
    end;
  if n < GetArrayLength(Lines) then
  begin
    FileCopy(KbFile, KbFile + '.faderport-backup', False);
    SetArrayLength(Output, n);
    SaveStringsToFile(KbFile, Output, False);
  end;
end;

//------------------------------------------------------------ wizard flow

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if not FileExists(AddBackslash(WizardDirValue) + 'reaper.ini') then
      Result := MsgBox(CustomMessage('NoReaperIni'), mbConfirmation, MB_YESNO) = IDYES;
  end
  else if CurPageID = wpReady then
    Result := WaitForReaperClosed;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  // a previous installation may have had other components
  if not WizardIsComponentSelected('cpp') then
    DeleteFile(ExpandConstant('{app}\UserPlugins\reaper_4irmann_faderport.dll'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  WithScripts: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    WithScripts := WizardIsComponentSelected('lua') or WizardIsComponentSelected('emulator');
    if WithScripts then
      WriteActionList;
    UpdateStartup(WithScripts);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and WizardIsComponentSelected('cpp') and WizardIsComponentSelected('lua') then
    WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 + CustomMessage('BothInstalled');
end;

//------------------------------------------------------------- uninstall

function InitializeUninstall: Boolean;
begin
  Result := WaitForReaperClosed;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    UpdateStartup(False);
    RemoveRegisteredActions;
  end;
end;

[UninstallDelete]
Type: files; Name: "{app}\Scripts\{#ScriptDir}\register_actions.txt"
Type: dirifempty; Name: "{app}\Scripts\{#ScriptDir}\faderport"
Type: dirifempty; Name: "{app}\Scripts\{#ScriptDir}"
