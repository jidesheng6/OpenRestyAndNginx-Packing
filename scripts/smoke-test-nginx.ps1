param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [int]$Port = 18080
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$InstallerPath = (Resolve-Path $InstallerPath).Path
$InstallDir = Join-Path $env:ProgramFiles "nginx"
$Uninstaller = Join-Path $InstallDir "unins000.exe"
$ConfPath = Join-Path $InstallDir "conf\nginx.conf"
$VhostDir = Join-Path $InstallDir "conf\vhost"
$StartMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\nginx"
$DesktopDir = Join-Path $env:PUBLIC "Desktop"
$DesktopBefore = @(Get-ChildItem $DesktopDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.lnk', '.url') } | Select-Object -ExpandProperty FullName)
$Marker = "# smoke-test upgrade marker 0123456789"
$VhostMarker = "# vhost marker kept across upgrade"

function Wait-For([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$Description) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try { if (& $Condition) { return $true } } catch { }
        Start-Sleep -Seconds 1
    }
    throw "Timed out waiting for: $Description"
}

function Get-HealthStatus([int]$P) {
    try {
        return (Invoke-WebRequest -Uri "http://127.0.0.1:$P/healthz" -UseBasicParsing -TimeoutSec 3).StatusCode
    } catch {
        return 0
    }
}

function Invoke-Installer([string]$Path, [string]$Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Installer exited with code $($process.ExitCode): $Path $Arguments"
    }
}

try {
    Write-Host "Installing $InstallerPath on port $Port"
    $installArgs = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /PORT=$Port /TASKS=`"startservice,addtopath,desktopicon`""
    Invoke-Installer $InstallerPath $installArgs

    Wait-For { (Get-Service -Name nginx -ErrorAction SilentlyContinue).Status -eq "Running" } 90 "nginx service running" | Out-Null
    Wait-For { (Get-HealthStatus $Port) -eq 200 } 60 "health endpoint on port $Port" | Out-Null

    $versionOutput = & (Join-Path $InstallDir "nginx.exe") -v 2>&1 | Out-String
    if ($versionOutput -notmatch "nginx version") {
        throw "nginx.exe -v did not report a version: $versionOutput"
    }
    Write-Host "nginx reports: $($versionOutput.Trim())"

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$InstallDir*") {
        throw "Install directory was not added to the machine PATH."
    }

    foreach ($iconName in @("nginx.ico", "nginx-start.ico", "nginx-stop.ico", "nginx-restart.ico", "nginx-web.ico")) {
        $iconPath = Join-Path $InstallDir "icons\$iconName"
        if (-not (Test-Path $iconPath)) { throw "Missing shortcut icon: $iconPath" }
    }

    $startLinks = @(Get-ChildItem $StartMenuDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.lnk', '.url') })
    if ($startLinks.Count -lt 6) {
        throw "Expected 6 Start Menu shortcuts, found $($startLinks.Count) in $StartMenuDir"
    }
    $desktopAfter = @(Get-ChildItem $DesktopDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.lnk', '.url') } | Select-Object -ExpandProperty FullName)
    $desktopNew = @($desktopAfter | Where-Object { $_ -notin $DesktopBefore })
    if ($desktopNew.Count -lt 4) {
        throw "Expected 4 new desktop shortcuts, found $($desktopNew.Count)"
    }

    if (-not (Test-Path $VhostDir)) { throw "Missing vhost directory: $VhostDir" }
    Add-Content -Path $ConfPath -Value $Marker -Encoding UTF8
    Add-Content -Path (Join-Path $VhostDir "smoke.conf") -Value $VhostMarker -Encoding UTF8

    Write-Host "Re-running installer to verify upgrade keeps configuration and vhost"
    Invoke-Installer $InstallerPath $installArgs
    Wait-For { (Get-Service -Name nginx -ErrorAction SilentlyContinue).Status -eq "Running" } 90 "nginx service running after upgrade" | Out-Null
    Wait-For { (Get-HealthStatus $Port) -eq 200 } 60 "health endpoint after upgrade" | Out-Null
    if (-not (Select-String -Path $ConfPath -Pattern ([regex]::Escape($Marker)) -Quiet)) {
        throw "Upgrade overwrote conf\nginx.conf; user configuration was not preserved."
    }
    if (-not (Select-String -Path (Join-Path $VhostDir "smoke.conf") -Pattern ([regex]::Escape($VhostMarker)) -Quiet)) {
        throw "Upgrade overwrote conf\vhost; user vhost configuration was not preserved."
    }

    Write-Host "Upgrade preserved user configuration and vhost directory"

    if (-not (Test-Path $Uninstaller)) { throw "Uninstaller not found: $Uninstaller" }
    $uninstallLog = Join-Path $env:RUNNER_TEMP "nginx-uninstall.log"
    $env:NGINX_KEEPCONF = "0"
    Invoke-Installer $Uninstaller "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /KEEPCONF=0 /LOG=`"$uninstallLog`""
    Remove-Item Env:\NGINX_KEEPCONF -ErrorAction SilentlyContinue

    Wait-For { -not (Get-Service -Name nginx -ErrorAction SilentlyContinue) } 60 "nginx service removal" | Out-Null

    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline -and (Test-Path $InstallDir)) { Start-Sleep -Seconds 1 }
    if (Test-Path $InstallDir) {
        $leftovers = Get-ChildItem $InstallDir -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 40 -ExpandProperty FullName
        if (Test-Path $uninstallLog) {
            Write-Host "----- uninstall log (tail) -----"
            Get-Content $uninstallLog -Tail 60 | Write-Host
            Write-Host "----- end uninstall log -----"
        }
        throw "Installation directory still exists after uninstall. Leftover files: $($leftovers -join '; ')"
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -like "*$InstallDir*") {
        throw "Install directory is still present in the machine PATH after uninstall."
    }

    $leftover = Get-Process nginx -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" }
    if ($leftover) { throw "nginx.exe processes are still running after uninstall." }

    $remainingLinks = @($desktopNew | Where-Object { Test-Path $_ })
    if ($remainingLinks.Count -gt 0) {
        throw "Desktop shortcuts were not removed: $($remainingLinks -join '; ')"
    }
    if (Test-Path $StartMenuDir) {
        $remainingStartLinks = @(Get-ChildItem $StartMenuDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.lnk', '.url') })
        if ($remainingStartLinks.Count -gt 0) {
            throw "Start Menu shortcuts were not removed: $($remainingStartLinks.FullName -join '; ')"
        }
    }

    Write-Host "Smoke test passed: install, upgrade with config/vhost preservation, and uninstall."
}
catch {
    Write-Warning $_.Exception.Message
    if (Test-Path $Uninstaller) {
        try { Invoke-Installer $Uninstaller "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /KEEPCONF=0" } catch { }
    }
    throw
}
