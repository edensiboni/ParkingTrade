<#
.SYNOPSIS
    Installs the Windows prerequisites for the ParkingTrade local backend:
    WSL2 and Docker Desktop.

.DESCRIPTION
    Must be run from an ELEVATED (Administrator) PowerShell window.
    The script is idempotent: it checks for each component first and only
    installs what is missing. Both installs can require a reboot; the script
    detects that and tells you clearly what to do next.

.NOTES
    Project : ParkingTrade
    Targets : Windows 10/11 with winget (App Installer) available.
#>

[CmdletBinding()]
param(
    # Skip the interactive "reboot now?" prompt at the end (just report instead).
    [switch] $NoRebootPrompt
)

# Native tools (wsl/winget) signal failure via exit code, not exceptions, so we
# keep going on non-terminating errors and check $LASTEXITCODE explicitly.
$ErrorActionPreference = 'Continue'

# ----------------------------------------------------------------------------
# Pretty console helpers
# ----------------------------------------------------------------------------
function Write-Step { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    [ OK ] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "    [WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "    [FAIL] $m" -ForegroundColor Red }

$RebootRequired = $false

Write-Host "============================================================" -ForegroundColor White
Write-Host " ParkingTrade - Windows backend prerequisites installer" -ForegroundColor White
Write-Host " (WSL2 + Docker Desktop)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

# ----------------------------------------------------------------------------
# 0. Must be Administrator
# ----------------------------------------------------------------------------
Write-Step "Verifying Administrator privileges"
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script is NOT running as Administrator."
    Write-Host "    Close this window, right-click Windows Terminal / PowerShell," -ForegroundColor Yellow
    Write-Host "    choose 'Run as administrator', then run the script again." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Elevated session confirmed."

# ----------------------------------------------------------------------------
# Helper: detect a pending reboot from the usual registry markers
# ----------------------------------------------------------------------------
function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sm -and $sm.PendingFileRenameOperations) { return $true }
    return $false
}

# ----------------------------------------------------------------------------
# 1. WSL2
# ----------------------------------------------------------------------------
Write-Step "Checking Windows Subsystem for Linux (WSL2)"
$wslInstalled = $false
try {
    # `wsl --version` returns 0 only when the modern (Store-based) WSL is present.
    & wsl.exe --version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch {
    $wslInstalled = $false
}

if ($wslInstalled) {
    Write-Ok "WSL is already installed."
} else {
    Write-Warn "WSL not detected. Installing WSL2 (enables VirtualMachinePlatform, the WSL2 kernel, and a default Linux distribution)..."
    try {
        # --no-launch stops the default distro from opening an interactive setup
        # that would block an automated run. Fall back if the flag is unsupported.
        & wsl.exe --install --no-launch
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "'--no-launch' not supported on this build; retrying 'wsl --install'..."
            & wsl.exe --install
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "WSL install command completed. A reboot is required to finish it."
            $RebootRequired = $true
        } else {
            Write-Err "WSL install returned exit code $LASTEXITCODE. Try manually:  wsl --install"
        }
    } catch {
        Write-Err "WSL installation threw an error: $($_.Exception.Message)"
        Write-Host "    Try manually in this window:  wsl --install" -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------------------
# 2. Docker Desktop
# ----------------------------------------------------------------------------
Write-Step "Checking Docker Desktop"
$dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
$dockerInstalled = (Test-Path $dockerExe) -or [bool](Get-Command docker -ErrorAction SilentlyContinue)

if ($dockerInstalled) {
    Write-Ok "Docker Desktop is already installed."
} else {
    Write-Warn "Docker Desktop not detected. Installing via winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Err "winget is unavailable. Install 'App Installer' from the Microsoft Store, then re-run this script."
    } else {
        try {
            & winget install --exact --id Docker.DockerDesktop `
                --accept-package-agreements --accept-source-agreements --silent
            $code = $LASTEXITCODE
            switch ($code) {
                0        { Write-Ok "Docker Desktop installed successfully." }
                3010     { Write-Ok "Docker Desktop installed (installer requests a reboot)."; $RebootRequired = $true }
                1641     { Write-Ok "Docker Desktop installed (installer is initiating a reboot)."; $RebootRequired = $true }
                -1978335189 { Write-Ok "Docker Desktop is already installed (winget: no applicable upgrade)." }
                default  { Write-Warn "winget finished with exit code $code. Scroll up to review its output." }
            }
        } catch {
            Write-Err "Docker Desktop installation threw an error: $($_.Exception.Message)"
        }
    }
}

# ----------------------------------------------------------------------------
# 3. Summary + reboot guidance
# ----------------------------------------------------------------------------
Write-Step "Summary"
if (Test-PendingReboot) { $RebootRequired = $true }

if ($RebootRequired) {
    Write-Host ""
    Write-Warn "A SYSTEM REBOOT IS REQUIRED before Docker/WSL2 will work."
    Write-Host "    After you reboot:" -ForegroundColor Yellow
    Write-Host "      1) Launch 'Docker Desktop' and accept the terms." -ForegroundColor Yellow
    Write-Host "      2) Wait until the whale icon in the tray is steady (engine running)." -ForegroundColor Yellow
    Write-Host "      3) Confirm with:   docker version" -ForegroundColor Yellow
    Write-Host "      4) Then the ParkingTrade backend is ready:  supabase start" -ForegroundColor Yellow
    Write-Host ""
    if (-not $NoRebootPrompt) {
        $answer = Read-Host "Reboot now? [y/N]"
        if ($answer -match '^(y|yes)$') {
            Write-Host "Rebooting in 5 seconds - press Ctrl+C to cancel..." -ForegroundColor Red
            Start-Sleep -Seconds 5
            Restart-Computer -Force
        } else {
            Write-Host "    OK - please reboot manually when you are ready." -ForegroundColor Yellow
        }
    }
} else {
    Write-Ok "No reboot flagged."
    Write-Host "    Launch Docker Desktop, wait for the engine, then run 'docker version' to confirm." -ForegroundColor Green
}

Write-Host "`nDone.`n" -ForegroundColor White
