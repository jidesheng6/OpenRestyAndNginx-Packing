; OpenResty Windows installer.
; Compile with: ISCC.exe /DAppVersion=1.31.8.1 installer\openresty.iss
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "OpenResty"
#define AppPublisher "jidesheng6"
#define AppURL "https://openresty.org/"
#define ServiceExeName "openresty-service.exe"
#define ServiceName "OpenResty"

[Setup]
AppId={{6F2E3C7A-9D41-4B8A-8E62-2C5F1A7D9B30}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoCompany={#AppPublisher}
DefaultDirName={autopf}\OpenResty
DefaultGroupName=OpenResty
DisableProgramGroupPage=yes
LicenseFile=assets\license-MIT.txt
OutputDir=Output
OutputBaseFilename=OpenResty-Setup-{#AppVersion}-win64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
UsePreviousAppDir=yes
ChangesEnvironment=yes
UninstallDisplayIcon={app}\nginx.exe
UninstallDisplayName={#AppName} {#AppVersion}
CloseApplications=no
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startservice"; Description: "Start the OpenResty service after installation"; GroupDescription: "Additional tasks:"
Name: "addtopath"; Description: "Add OpenResty to the system PATH"; GroupDescription: "Additional tasks:"

[Files]
Source: "..\payload\app\*"; DestDir: "{app}"; Excludes: "conf\*,html\*,logs\*"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\payload\app\conf\*"; DestDir: "{app}\conf"; Excludes: "nginx.conf"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs
Source: "..\payload\app\html\*"; DestDir: "{app}\html"; Excludes: "index.html"; Flags: onlyifdoesntexist recursesubdirs createallsubdirs
Source: "..\payload\conf-overlay\nginx.conf"; DestDir: "{app}\conf"; Flags: onlyifdoesntexist
Source: "..\payload\html-overlay\index.html"; DestDir: "{app}\html"; Flags: onlyifdoesntexist
Source: "..\payload\{#ServiceExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\payload\openresty-service.xml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\payload\license-MIT.txt"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\payload\version.txt"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{app}\conf"
Name: "{app}\html"
Name: "{app}\logs"

[Icons]
Name: "{group}\Start OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "start"; WorkingDir: "{app}"
Name: "{group}\Stop OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "stop"; WorkingDir: "{app}"
Name: "{group}\Restart OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "restart"; WorkingDir: "{app}"
Name: "{group}\Open Install Folder"; Filename: "{app}"
Name: "{group}\Open Test Page"; Filename: "http://127.0.0.1:{code:GetHttpPort}/"
Name: "{group}\Uninstall OpenResty"; Filename: "{uninstallexe}"

[Registry]
Root: HKLM; Subkey: "Software\OpenResty"; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#ServiceExeName}"; Parameters: "uninstall"; Flags: runhidden waituntilterminated; StatusMsg: "Removing previous OpenResty service registration..."
Filename: "{app}\{#ServiceExeName}"; Parameters: "install"; Flags: runhidden waituntilterminated; StatusMsg: "Registering the OpenResty service..."
Filename: "http://127.0.0.1:{code:GetHttpPort}/"; Description: "Open the OpenResty test page"; Flags: shellexec nowait postinstall skipifsilent; Check: ShouldOfferTestPage

[UninstallRun]
Filename: "{app}\{#ServiceExeName}"; Parameters: "stop"; RunOnceId: "StopOpenRestyService"; Flags: runhidden waituntilterminated
Filename: "{app}\{#ServiceExeName}"; Parameters: "uninstall"; RunOnceId: "RemoveOpenRestyService"; Flags: runhidden waituntilterminated

[Code]
const
  EnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

var
  HttpPort: Integer;
  DefaultPort: Integer;
  HasExistingInstall: Boolean;
  PortPage: TInputQueryWizardPage;
  ServiceHealthy: Boolean;
  PerlFound: Boolean;
  KeepConfig: Boolean;

function GetHttpPort(Param: String): String;
begin
  Result := IntToStr(HttpPort);
end;

function ShouldOfferTestPage: Boolean;
begin
  Result := ServiceHealthy;
end;

function ReadExistingInstall: Boolean;
var
  InstallDir: String;
begin
  Result := False;
  if RegQueryStringValue(HKLM, 'Software\OpenResty', 'InstallDir', InstallDir) then
    Result := FileExists(AddBackslash(InstallDir) + 'nginx.exe');
end;

function DetectPortFromConf(const InstallDir: String; var Port: Integer): Boolean;
var
  ConfPath: String;
  Lines: TArrayOfString;
  I: Integer;
  J: Integer;
  S: String;
  Digits: String;
begin
  Result := False;
  ConfPath := AddBackslash(InstallDir) + 'conf\nginx.conf';
  if not FileExists(ConfPath) then
    Exit;
  if not LoadStringsFromFile(ConfPath, Lines) then
    Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    S := Trim(Lines[I]);
    if (Length(S) >= 6) and (CompareText(Copy(S, 1, 6), 'listen') = 0) then
    begin
      J := 7;
      while (J <= Length(S)) and ((S[J] = ' ') or (S[J] = #9)) do
        J := J + 1;
      Digits := '';
      while (J <= Length(S)) and (S[J] >= '0') and (S[J] <= '9') do
      begin
        Digits := Digits + S[J];
        J := J + 1;
      end;
      if Digits <> '' then
      begin
        Port := StrToIntDef(Digits, Port);
        Result := True;
        Exit;
      end;
    end;
  end;
end;

function InitializeSetup: Boolean;
var
  PortText: String;
  PortValue: Integer;
  InstallDir: String;
begin
  Result := True;
  DefaultPort := 80;
  HasExistingInstall := ReadExistingInstall;

  if RegQueryStringValue(HKLM, 'Software\OpenResty', 'HttpPort', PortText) then
  begin
    PortValue := StrToIntDef(PortText, 80);
    if (PortValue > 0) and (PortValue < 65536) then
      DefaultPort := PortValue;
  end;

  if HasExistingInstall and RegQueryStringValue(HKLM, 'Software\OpenResty', 'InstallDir', InstallDir) then
  begin
    if DetectPortFromConf(InstallDir, PortValue) then
      DefaultPort := PortValue;
  end;

  PortText := ExpandConstant('{param:PORT|}');
  if PortText <> '' then
  begin
    PortValue := StrToIntDef(PortText, -1);
    if (PortValue <= 0) or (PortValue > 65535) then
    begin
      MsgBox('Invalid /PORT value: ' + PortText, mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if not HasExistingInstall then
      DefaultPort := PortValue;
  end;

  HttpPort := DefaultPort;
end;

procedure InitializeWizard;
begin
  ServiceHealthy := False;
  if (not HasExistingInstall) and (ExpandConstant('{param:PORT|}') = '') then
  begin
    PortPage := CreateInputQueryPage(wpSelectDir,
      'OpenResty HTTP Port',
      'Choose the HTTP port OpenResty listens on.',
      'The installer writes this port into conf\nginx.conf. You can change it later in the configuration file.');
    PortPage.Add('HTTP port (&1-65535):', False);
    PortPage.Values[0] := IntToStr(DefaultPort);
  end;
end;

function IsPortInUse(Port: Integer): Boolean;
var
  ResultCode: Integer;
  TmpFile: String;
  Lines: TArrayOfString;
  I: Integer;
  Needle: String;
begin
  Result := False;
  TmpFile := ExpandConstant('{tmp}\netstat-openresty.txt');
  if Exec(ExpandConstant('{cmd}'), '/c netstat -ano -p TCP > "' + TmpFile + '"', '',
          SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if LoadStringsFromFile(TmpFile, Lines) then
    begin
      Needle := ':' + IntToStr(Port) + ' ';
      for I := 0 to GetArrayLength(Lines) - 1 do
      begin
        if (Pos(Needle, Lines[I]) > 0) and (Pos('LISTENING', Lines[I]) > 0) then
        begin
          Result := True;
          Exit;
        end;
      end;
    end;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  PortValue: Integer;
begin
  Result := True;
  if Assigned(PortPage) and (CurPageID = PortPage.ID) then
  begin
    PortValue := StrToIntDef(Trim(PortPage.Values[0]), -1);
    if (PortValue <= 0) or (PortValue > 65535) then
    begin
      MsgBox('Please enter a port number between 1 and 65535.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if IsPortInUse(PortValue) then
    begin
      MsgBox('TCP port ' + IntToStr(PortValue) + ' is already in use. Please choose another port.',
        mbError, MB_OK);
      Result := False;
      Exit;
    end;
    HttpPort := PortValue;
  end;
end;

procedure StopNginxProcessesInAppDir;
var
  ResultCode: Integer;
  AppDir: String;
  Command: String;
begin
  AppDir := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  Command := '-NoProfile -ExecutionPolicy Bypass -Command "Get-Process nginx -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ''' + AppDir + '\*'' } | Stop-Process -Force"';
  Exec('powershell.exe', Command, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure StopServiceIfExists;
var
  ResultCode: Integer;
  ExePath: String;
begin
  ExePath := ExpandConstant('{app}\{#ServiceExeName}');
  if FileExists(ExePath) then
  begin
    Exec(ExePath, 'stop', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
    Exec(ExePath, 'uninstall', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  StopServiceIfExists;
  Sleep(500);
  StopNginxProcessesInAppDir;
end;

procedure ApplyPortToConf;
var
  ConfPath: String;
  ContentA: AnsiString;
  Content: String;
begin
  ConfPath := ExpandConstant('{app}\conf\nginx.conf');
  if FileExists(ConfPath) then
  begin
    if LoadStringFromFile(ConfPath, ContentA) then
    begin
      Content := ContentA;
      if Pos('__HTTP_PORT__', Content) > 0 then
      begin
        StringChangeEx(Content, '__HTTP_PORT__', IntToStr(HttpPort), True);
        ContentA := Content;
        SaveStringToFile(ConfPath, ContentA, False);
      end;
    end;
  end;
end;

function HttpGetStatus(const Url: String): Integer;
var
  Request: Variant;
begin
  Result := 0;
  try
    Request := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Request.SetProxy(2, '');
    Request.Open('GET', Url, False);
    Request.SetTimeouts(2000, 2000, 3000, 5000);
    Request.Send;
    Result := Request.Status;
  except
    Result := 0;
  end;
end;

function WaitForHealth(TimeoutMs: Integer): Boolean;
var
  Elapsed: Integer;
  Url: String;
begin
  Result := False;
  Url := 'http://127.0.0.1:' + IntToStr(HttpPort) + '/healthz';
  Elapsed := 0;
  while Elapsed < TimeoutMs do
  begin
    if HttpGetStatus(Url) = 200 then
    begin
      Result := True;
      Exit;
    end;
    Sleep(1000);
    Elapsed := Elapsed + 1000;
  end;
end;

function PerlAvailable: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), '/c where perl >nul 2>nul', '',
                 SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

procedure BroadcastEnvironmentChange;
begin
  { New processes receive the updated PATH from the registry. Explorer caches its
    environment, so a sign-out/sign-in may be required for existing shells. }
end;

function NeedsAddPath(const AppDir: String): Boolean;
var
  OrigPath: String;
begin
  if not RegQueryStringValue(HKLM, EnvironmentKey, 'Path', OrigPath) then
  begin
    Result := True;
    Exit;
  end;
  Result := Pos(';' + Uppercase(AppDir) + ';', ';' + Uppercase(OrigPath) + ';') = 0;
end;

procedure AddToPath;
var
  OrigPath: String;
  AppDir: String;
begin
  AppDir := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  if not RegQueryStringValue(HKLM, EnvironmentKey, 'Path', OrigPath) then
    OrigPath := '';
  if OrigPath = '' then
    RegWriteExpandStringValue(HKLM, EnvironmentKey, 'Path', AppDir)
  else
    RegWriteExpandStringValue(HKLM, EnvironmentKey, 'Path', OrigPath + ';' + AppDir);
  BroadcastEnvironmentChange;
end;

procedure RemoveFromPath;
var
  OrigPath: String;
  AppDir: String;
  Rest: String;
  Part: String;
  NewPath: String;
  P: Integer;
begin
  AppDir := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
  if not RegQueryStringValue(HKLM, EnvironmentKey, 'Path', OrigPath) then
    Exit;
  NewPath := '';
  Rest := OrigPath;
  while Rest <> '' do
  begin
    P := Pos(';', Rest);
    if P = 0 then
    begin
      Part := Rest;
      Rest := '';
    end
    else
    begin
      Part := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, Length(Rest));
    end;
    if (Part <> '') and (CompareText(RemoveBackslashUnlessRoot(Part), AppDir) <> 0) then
    begin
      if NewPath <> '' then
        NewPath := NewPath + ';';
      NewPath := NewPath + Part;
    end;
  end;
  RegWriteExpandStringValue(HKLM, EnvironmentKey, 'Path', NewPath);
  BroadcastEnvironmentChange;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ServiceExe: String;
  NoStart: String;
begin
  if CurStep = ssPostInstall then
  begin
    ApplyPortToConf;
    RegWriteStringValue(HKLM, 'Software\OpenResty', 'InstallDir', ExpandConstant('{app}'));
    RegWriteStringValue(HKLM, 'Software\OpenResty', 'HttpPort', IntToStr(HttpPort));

    if WizardIsTaskSelected('addtopath') and NeedsAddPath(RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) then
      AddToPath;

    NoStart := ExpandConstant('{param:NOSTART|0}');
    if (NoStart <> '1') and WizardIsTaskSelected('startservice') then
    begin
      ServiceExe := ExpandConstant('{app}\{#ServiceExeName}');
      Exec(ServiceExe, 'start', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
      ServiceHealthy := WaitForHealth(60000);
    end;

    PerlFound := PerlAvailable;
    if (not PerlFound) and (not WizardSilent) then
      MsgBox('Perl was not found on this system.' + #13#10 +
             'The OpenResty service does not need Perl, but the "resty" command-line tool does.' + #13#10 +
             'Install Strawberry Perl from https://strawberryperl.com/ if you need resty.',
             mbInformation, MB_OK);
  end;
end;

function InitializeUninstall: Boolean;
var
  KeepParam: String;
  Answer: Integer;
begin
  Result := True;
  KeepParam := ExpandConstant('{param:KEEPCONF|}');
  if KeepParam = '0' then
    KeepConfig := False
  else if KeepParam = '1' then
    KeepConfig := True
  else if UninstallSilent then
    KeepConfig := True
  else
  begin
    Answer := MsgBox('Keep the configuration (conf), web pages (html) and logs (logs)?' + #13#10 +
                     'Choose Yes to keep them, No to delete them.',
                     mbConfirmation, MB_YESNO);
    KeepConfig := (Answer = IDYES);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  ServiceExe: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    ServiceExe := ExpandConstant('{app}\{#ServiceExeName}');
    if FileExists(ServiceExe) then
      Exec(ServiceExe, 'stop', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
    StopNginxProcessesInAppDir;
  end;
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveFromPath;
    if not KeepConfig then
    begin
      DelTree(ExpandConstant('{app}\conf'), True, True, True);
      DelTree(ExpandConstant('{app}\html'), True, True, True);
      DelTree(ExpandConstant('{app}\logs'), True, True, True);
    end;
  end;
end;
