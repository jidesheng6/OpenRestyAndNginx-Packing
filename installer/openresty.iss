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
VersionInfoProductVersion={#AppVersion}
VersionInfoDescription={#AppName} {#AppVersion} Windows 安装程序
VersionInfoCompany={#AppPublisher}
DefaultDirName={autopf}\OpenResty
DefaultGroupName=OpenResty
DisableProgramGroupPage=yes
LicenseFile=assets\license-MIT.txt
SetupIconFile=assets\openresty.ico
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
UninstallDisplayIcon={app}\icons\openresty.ico
UninstallDisplayName={#AppName} {#AppVersion}
CloseApplications=no
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "languages\ChineseSimplified.isl"

[Tasks]
Name: "startservice"; Description: "安装完成后自动启动 OpenResty 服务"; GroupDescription: "附加任务："
Name: "addtopath"; Description: "将 OpenResty 添加到系统 PATH 环境变量"; GroupDescription: "附加任务："
Name: "desktopicon"; Description: "创建桌面快捷方式（启动、停止、重启、打开测试页）"; GroupDescription: "附加任务："; Flags: unchecked

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
Source: "assets\openresty.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "assets\openresty-start.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "assets\openresty-stop.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "assets\openresty-restart.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "assets\openresty-web.ico"; DestDir: "{app}\icons"; Flags: ignoreversion

[Dirs]
Name: "{app}\conf"
Name: "{app}\html"
Name: "{app}\logs"

[Icons]
Name: "{group}\启动 OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "start"; WorkingDir: "{app}"; IconFilename: "{app}\icons\openresty-start.ico"
Name: "{group}\停止 OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "stop"; WorkingDir: "{app}"; IconFilename: "{app}\icons\openresty-stop.ico"
Name: "{group}\重启 OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "restart"; WorkingDir: "{app}"; IconFilename: "{app}\icons\openresty-restart.ico"
Name: "{group}\打开安装目录"; Filename: "{app}"; IconFilename: "{app}\icons\openresty.ico"
Name: "{group}\打开测试页"; Filename: "http://127.0.0.1:{code:GetHttpPort}/"; IconFilename: "{app}\icons\openresty-web.ico"
Name: "{group}\卸载 OpenResty"; Filename: "{uninstallexe}"; IconFilename: "{app}\icons\openresty.ico"
Name: "{commondesktop}\启动 OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "start"; WorkingDir: "{app}"; IconFilename: "{app}\icons\openresty-start.ico"; Tasks: desktopicon
Name: "{commondesktop}\停止 OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "stop"; WorkingDir: "{app}"; IconFilename: "{app}\icons\openresty-stop.ico"; Tasks: desktopicon
Name: "{commondesktop}\重启 OpenResty"; Filename: "{app}\{#ServiceExeName}"; Parameters: "restart"; WorkingDir: "{app}"; IconFilename: "{app}\icons\openresty-restart.ico"; Tasks: desktopicon
Name: "{commondesktop}\OpenResty 测试页"; Filename: "http://127.0.0.1:{code:GetHttpPort}/"; IconFilename: "{app}\icons\openresty-web.ico"; Tasks: desktopicon

[Registry]
Root: HKLM; Subkey: "Software\OpenResty"; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#ServiceExeName}"; Parameters: "uninstall"; WorkingDir: "{tmp}"; Flags: runhidden waituntilterminated; StatusMsg: "正在移除旧的 OpenResty 服务注册..."
Filename: "{app}\{#ServiceExeName}"; Parameters: "install"; WorkingDir: "{tmp}"; Flags: runhidden waituntilterminated; StatusMsg: "正在注册 OpenResty 服务..."

[UninstallRun]
Filename: "{app}\{#ServiceExeName}"; Parameters: "stop"; WorkingDir: "{tmp}"; RunOnceId: "StopOpenRestyService"; Flags: runhidden waituntilterminated
Filename: "{app}\{#ServiceExeName}"; Parameters: "uninstall"; WorkingDir: "{tmp}"; RunOnceId: "RemoveOpenRestyService"; Flags: runhidden waituntilterminated

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
  TestPageOpened: Boolean;

function BoolText(const B: Boolean): String;
begin
  if B then
    Result := 'True'
  else
    Result := 'False';
end;

function GetHttpPort(Param: String): String;
begin
  Result := IntToStr(HttpPort);
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
      MsgBox('无效的 /PORT 参数：' + PortText, mbError, MB_OK);
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
  TestPageOpened := False;
  if (not HasExistingInstall) and (ExpandConstant('{param:PORT|}') = '') then
  begin
    PortPage := CreateInputQueryPage(wpSelectDir,
      'OpenResty HTTP 端口',
      '请选择 OpenResty 监听的 HTTP 端口。',
      '安装程序会将该端口写入 conf\nginx.conf。之后也可以直接修改配置文件。');
    PortPage.Add('HTTP 端口（1-65535）：', False);
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
      MsgBox('请输入 1 到 65535 之间的端口号。', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if IsPortInUse(PortValue) then
    begin
      MsgBox('TCP 端口 ' + IntToStr(PortValue) + ' 已被占用，请换一个端口。',
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
    Exec(ExePath, 'stop', ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
    Exec(ExePath, 'uninstall', ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
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
      Exec(ServiceExe, 'start', ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
      ServiceHealthy := WaitForHealth(60000);
    end;

    PerlFound := PerlAvailable;
    if (not PerlFound) and (not WizardSilent) then
      MsgBox('未检测到 Perl。' + #13#10 +
             'OpenResty 服务本身不需要 Perl，但“resty”命令行工具需要。' + #13#10 +
             '如需使用 resty，请从 https://strawberryperl.com/ 安装 Strawberry Perl。',
             mbInformation, MB_OK);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  ResultCode: Integer;
begin
  if CurPageID = wpFinished then
  begin
    if ServiceHealthy then
      WizardForm.FinishedLabel.Caption :=
        'OpenResty {#AppVersion} 已安装完成并正在运行。' + #13#10 +
        '测试页：http://127.0.0.1:' + IntToStr(HttpPort) + '/'
    else if (ExpandConstant('{param:NOSTART|0}') <> '1') and WizardIsTaskSelected('startservice') then
      WizardForm.FinishedLabel.Caption :=
        '安装已完成，但 OpenResty 服务未能通过健康检查。' + #13#10 +
        '请查看日志：' + ExpandConstant('{app}\logs\error.log') + #13#10 +
        '也可以稍后从开始菜单运行“重启 OpenResty”。'
    else
      WizardForm.FinishedLabel.Caption :=
        'OpenResty {#AppVersion} 已安装完成。服务未启动，可从开始菜单运行“启动 OpenResty”。';

    if ServiceHealthy and (not TestPageOpened) and (not WizardSilent) then
    begin
      TestPageOpened := True;
      ShellExec('open', 'http://127.0.0.1:' + IntToStr(HttpPort) + '/', '', '',
        SW_SHOWNORMAL, ewNoWait, ResultCode);
    end;
  end;
end;

function InitializeUninstall: Boolean;
var
  KeepParam: String;
  Answer: Integer;
begin
  Result := True;
  KeepParam := ExpandConstant('{param:KEEPCONF|}');
  if KeepParam = '' then
    KeepParam := GetEnv('OPENRESTY_KEEPCONF');
  Log('KEEPCONF value: "' + KeepParam + '"');
  if KeepParam = '0' then
    KeepConfig := False
  else if KeepParam = '1' then
    KeepConfig := True
  else if UninstallSilent then
    KeepConfig := True
  else
  begin
    Answer := MsgBox('是否保留配置文件（conf）、网页文件（html）和日志（logs）？' + #13#10 +
                     '选择“是”保留，选择“否”删除。',
                     mbConfirmation, MB_YESNO);
    KeepConfig := (Answer = IDYES);
  end;
  Log('KeepConfig: ' + BoolText(KeepConfig));
end;

procedure RemoveServiceRegistration;
var
  ResultCode: Integer;
  I: Integer;
begin
  Exec(ExpandConstant('{cmd}'), '/c sc stop OpenResty >nul 2>nul', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1500);
  for I := 1 to 5 do
  begin
    Exec(ExpandConstant('{cmd}'), '/c sc delete OpenResty >nul 2>nul', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1000);
  end;
  Log('Service registration cleanup attempted.');
end;

procedure DeleteUserData;
begin
  Log('Deleting conf: ' + BoolText(DelTree(ExpandConstant('{app}\conf'), True, True, True)));
  Log('Deleting html: ' + BoolText(DelTree(ExpandConstant('{app}\html'), True, True, True)));
  Log('Deleting logs: ' + BoolText(DelTree(ExpandConstant('{app}\logs'), True, True, True)));
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
      Exec(ServiceExe, 'stop', ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
    StopNginxProcessesInAppDir;
    RemoveServiceRegistration;
  end;
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveServiceRegistration;
    RemoveFromPath;
    Sleep(1000);
    if not KeepConfig then
      DeleteUserData;
  end;
  if (CurUninstallStep = usDone) and (not KeepConfig) then
  begin
    DeleteUserData;
    RemoveDir(ExpandConstant('{app}\conf'));
    RemoveDir(ExpandConstant('{app}\html'));
    RemoveDir(ExpandConstant('{app}\logs'));
    RemoveDir(ExpandConstant('{app}'));
    if DirExists(ExpandConstant('{app}')) then
      Exec(ExpandConstant('{cmd}'),
        '/c ping 127.0.0.1 -n 4 >nul & rmdir /s /q "' + ExpandConstant('{app}') + '"',
        ExpandConstant('{tmp}'), SW_HIDE, ewNoWait, ResultCode);
  end;
end;
