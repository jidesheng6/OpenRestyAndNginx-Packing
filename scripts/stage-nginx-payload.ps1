param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$StageDir = "",
    [string]$PayloadDir = "",
    [string]$WinSWVersion = "2.13.0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StageDir)) { $StageDir = Join-Path $RepoRoot ".build/stage/nginx-$Version" }
if ([string]::IsNullOrWhiteSpace($PayloadDir)) { $PayloadDir = Join-Path $RepoRoot "payload-nginx" }

New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

# Download the official nginx/Windows zip and unpack it into the stage dir.
$ZipPath = Join-Path $StageDir "nginx-$Version.zip"
if (-not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -lt 100KB) {
    $Url = "https://nginx.org/download/nginx-$Version.zip"
    Write-Host "Downloading official nginx/Windows $Version"
    $attempt = 0
    while ($true) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing -TimeoutSec 180
            break
        } catch {
            $attempt++
            if ($attempt -ge 5) { throw "Failed to download $Url : $_" }
            Start-Sleep -Seconds 3
        }
    }
}
$UnpackDir = Join-Path $StageDir "unpacked"
if (Test-Path $UnpackDir) { Remove-Item -Recurse -Force $UnpackDir }
New-Item -ItemType Directory -Force -Path $UnpackDir | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $UnpackDir -Force
$AppSource = Get-ChildItem -Path $UnpackDir -Directory | Where-Object { $_.Name -like "nginx-*" } | Select-Object -First 1
if (-not $AppSource -or -not (Test-Path (Join-Path $AppSource.FullName "nginx.exe"))) {
    Get-ChildItem -Path $UnpackDir -Recurse -File | Select-Object -First 50 FullName | Format-Table -AutoSize | Out-String | Write-Host
    throw "nginx.exe not found in official zip"
}

if (Test-Path $PayloadDir) { Remove-Item -Recurse -Force $PayloadDir }
New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null

Write-Host "Staging nginx $Version from $($AppSource.FullName)"
$AppDir = Join-Path $PayloadDir "app"
Copy-Item -Path $AppSource.FullName -Destination $AppDir -Recurse -Force

# Ensure vhost directory exists inside the staged conf.
New-Item -ItemType Directory -Force -Path (Join-Path $AppDir "conf\vhost") | Out-Null
Copy-Item -Path (Join-Path $RepoRoot "packaging\linux\conf.d\README") -Destination (Join-Path $AppDir "conf\vhost\README") -Force

$OverlayDir = Join-Path $PayloadDir "conf-overlay"
New-Item -ItemType Directory -Force -Path $OverlayDir | Out-Null
Copy-Item -Path (Join-Path $RepoRoot "installer\conf\nginx.conf") -Destination (Join-Path $OverlayDir "nginx.conf") -Force

$HtmlOverlayDir = Join-Path $PayloadDir "html-overlay"
New-Item -ItemType Directory -Force -Path $HtmlOverlayDir | Out-Null
$IndexTemplate = Get-Content -Raw (Join-Path $RepoRoot "installer\html\nginx-index.html")
$IndexContent = $IndexTemplate.Replace("{{VERSION}}", "nginx $Version")
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
Copy-Item -Path $WinSWCache -Destination (Join-Path $PayloadDir "nginx-service.exe") -Force

$ServiceXml = @"
<service>
  <id>nginx</id>
  <name>nginx</name>
  <description>nginx（高性能 HTTP 服务器与反向代理），由 WinSW 管理。</description>
  <executable>%BASE%\nginx.exe</executable>
  <arguments>-p "%BASE%" -c conf/nginx.conf</arguments>
  <workingdirectory>%BASE%</workingdirectory>
  <stopexecutable>%BASE%\nginx.exe</stopexecutable>
  <stoparguments>-p "%BASE%" -c conf/nginx.conf -s quit</stoparguments>
  <startmode>Automatic</startmode>
  <delayedAutoStart>false</delayedAutoStart>
  <log mode="none"/>
  <onfailure action="restart" delay="10 sec"/>
  <resetfailure>1 hour</resetfailure>
</service>
"@
[System.IO.File]::WriteAllText((Join-Path $PayloadDir "nginx-service.xml"), $ServiceXml, (New-Object System.Text.UTF8Encoding($false)))

Copy-Item -Path (Join-Path $RepoRoot "installer\assets\license-MIT.txt") -Destination (Join-Path $PayloadDir "license-MIT.txt") -Force

$VersionInfo = @"
nginx $Version
使用 nginx.org 官方 Windows 二进制。
构建时间：$((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")) UTC
"@
[System.IO.File]::WriteAllText((Join-Path $PayloadDir "version.txt"), $VersionInfo, (New-Object System.Text.UTF8Encoding($false)))

$files = Get-ChildItem -Path $PayloadDir -Recurse -File
$sizeMb = [math]::Round((($files | Measure-Object -Property Length -Sum).Sum / 1MB), 1)
Write-Host "Payload ready: $($files.Count) files, $sizeMb MB -> $PayloadDir"
