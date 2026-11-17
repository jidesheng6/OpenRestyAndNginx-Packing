param(
    [Parameter(Mandatory = $true)][string]$InstallerPath,
    [int]$Port = 18080
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$InstallerPath = (Resolve-Path $InstallerPath).Path
$InstallDir = Join-Path $env:ProgramFiles "OpenResty"
$Uninstaller = Join-Path $InstallDir "unins000.exe"
$ConfPath = Join-Path $InstallDir "conf\nginx.conf"
$Marker = "# smoke-test upgrade marker 0123456789"

function Wait-For([scriptblock]$Condition, [int]$TimeoutSeconds, [string]$Description) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            if (& $Condition) { return $true }
        } catch { }
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
    Invoke-Installer $InstallerPath "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /PORT=$Port"

    Wait-For { (Get-Service -Name OpenResty -ErrorAction SilentlyContinue).Status -eq "Running" } 90 "OpenResty service running" | Out-Null
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

    if (-not (Test-Path $ConfPath)) { throw "Missing configuration file: $ConfPath" }
    Add-Content -Path $ConfPath -Value $Marker -Encoding UTF8

    Write-Host "Re-running installer to verify upgrade keeps configuration"
    Invoke-Installer $InstallerPath "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /PORT=$Port"
    Wait-For { (Get-Service -Name OpenResty -ErrorAction SilentlyContinue).Status -eq "Running" } 90 "OpenResty service running after upgrade" | Out-Null
    Wait-For { (Get-HealthStatus $Port) -eq 200 } 60 "health endpoint after upgrade" | Out-Null
    if (-not (Select-String -Path $ConfPath -Pattern ([regex]::Escape($Marker)) -Quiet)) {
        throw "Upgrade overwrote conf\\nginx.conf; user configuration was not preserved."
    }

    Write-Host "Upgrade preserved user configuration"

    if (-not (Test-Path $Uninstaller)) { throw "Uninstaller not found: $Uninstaller" }
    Invoke-Installer $Uninstaller "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /KEEPCONF=0"

    Wait-For { -not (Get-Service -Name OpenResty -ErrorAction SilentlyContinue) } 60 "OpenResty service removal" | Out-Null
    Wait-For { -not (Test-Path $InstallDir) } 60 "installation directory removal" | Out-Null

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -like "*$InstallDir*") {
        throw "Install directory is still present in the machine PATH after uninstall."
    }

    $leftover = Get-Process nginx -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$InstallDir\*" }
    if ($leftover) { throw "nginx.exe processes are still running after uninstall." }

    Write-Host "Smoke test passed: install, upgrade with config preservation, and uninstall."
}
catch {
    Write-Warning $_.Exception.Message
    if (Test-Path $Uninstaller) {
        try { Invoke-Installer $Uninstaller "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /KEEPCONF=0" } catch { }
    }
    throw
}
