param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$StageDir = "",
    [string]$PayloadDir = "",
    [string]$WinSWVersion = "2.13.0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StageDir)) { $StageDir = Join-Path $RepoRoot ".build/stage/openresty" }
if ([string]::IsNullOrWhiteSpace($PayloadDir)) { $PayloadDir = Join-Path $RepoRoot "payload" }

$StageDir = (Resolve-Path $StageDir).Path
$NginxExe = Join-Path $StageDir "nginx.exe"
if (-not (Test-Path $NginxExe)) {
    Get-ChildItem -Path $StageDir -Recurse -File | Select-Object -First 50 FullName | Format-Table -AutoSize | Out-String | Write-Host
    throw "nginx.exe not found in stage directory: $StageDir"
}

if (Test-Path $PayloadDir) { Remove-Item -Recurse -Force $PayloadDir }
New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null

Write-Host "Staging OpenResty $Version from $StageDir"
$AppDir = Join-Path $PayloadDir "app"
Copy-Item -Path $StageDir -Destination $AppDir -Recurse -Force

$OverlayDir = Join-Path $PayloadDir "conf-overlay"
New-Item -ItemType Directory -Force -Path $OverlayDir | Out-Null
Copy-Item -Path (Join-Path $RepoRoot "installer/conf/nginx.conf") -Destination (Join-Path $OverlayDir "nginx.conf") -Force

$HtmlOverlayDir = Join-Path $PayloadDir "html-overlay"
New-Item -ItemType Directory -Force -Path $HtmlOverlayDir | Out-Null
$IndexTemplate = Get-Content -Raw (Join-Path $RepoRoot "installer/html/index.html")
$IndexContent = $IndexTemplate.Replace("{{VERSION}}", "OpenResty $Version")
[System.IO.File]::WriteAllText((Join-Path $HtmlOverlayDir "index.html"), $IndexContent, (New-Object System.Text.UTF8Encoding($false)))

$CacheDir = Join-Path $RepoRoot ".cache"
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
$WinSWCache = Join-Path $CacheDir "WinSW-x64-$WinSWVersion.exe"
if (-not (Test-Path $WinSWCache) -or (Get-Item $WinSWCache).Length -lt 5MB) {
    $Url = "https://github.com/winsw/winsw/releases/download/v$WinSWVersion/WinSW-x64.exe_Release"
    Write-Host "Downloading WinSW $WinSWVersion"
    $attempt = 0
    while ($true) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $WinSWCache -UseBasicParsing -TimeoutSec 120
            break
        } catch {
            $attempt++
            if ($attempt -ge 5) { throw "Failed to download WinSW: $_" }
            Start-Sleep -Seconds 3
        }
    }
}
Copy-Item -Path $WinSWCache -Destination (Join-Path $PayloadDir "openresty-service.exe") -Force

$ServiceXml = @"
<service>
  <id>OpenResty</id>
  <name>OpenResty</name>
  <description>OpenResty (Nginx + LuaJIT) web platform managed by WinSW.</description>
  <executable>%BASE%\nginx.exe</executable>
  <arguments>-p "%BASE%" -c conf/nginx.conf</arguments>
  <workingdirectory>%BASE%</workingdirectory>
  <stopexecutable>%BASE%\nginx.exe</stopexecutable>
  <stoparguments>-p "%BASE%" -c conf/nginx.conf -s quit</stoparguments>
  <startmode>Automatic</startmode>
  <delayedAutoStart>false</delayedAutoStart>
  <logpath>%BASE%\logs</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>8</keepFiles>
  </log>
  <onfailure action="restart" delay="10 sec"/>
  <resetfailure>1 hour</resetfailure>
</service>
"@
[System.IO.File]::WriteAllText((Join-Path $PayloadDir "openresty-service.xml"), $ServiceXml, (New-Object System.Text.UTF8Encoding($false)))

Copy-Item -Path (Join-Path $RepoRoot "installer/assets/license-MIT.txt") -Destination (Join-Path $PayloadDir "license-MIT.txt") -Force

$VersionInfo = @"
OpenResty $Version
Built from the official source tarball with MSYS2 / MinGW64.
Build date: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")) UTC
"@
[System.IO.File]::WriteAllText((Join-Path $PayloadDir "version.txt"), $VersionInfo, (New-Object System.Text.UTF8Encoding($false)))

$files = Get-ChildItem -Path $PayloadDir -Recurse -File
$sizeMb = [math]::Round((($files | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
Write-Host "Payload ready: $($files.Count) files, $sizeMb MB -> $PayloadDir"
