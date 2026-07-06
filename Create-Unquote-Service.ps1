#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Lab setup: Unquoted Service Path
    Creates a service with an unquoted binary path containing spaces.
    User 'dave' has Modify on the intermediate directory — can plant a hijack binary.

.NOTES
    Run as Administrator before handing machine to student (dave).
    Student goal: drop Current.exe in "C:\Program Files\Enterprise Apps\", restart service, gain SYSTEM.
#>

$ErrorActionPreference = "Stop"

$SERVICE_NAME = "GammaSvc"
$SERVICE_DISP = "Gamma Enterprise Service"
$BINARY_DIR   = "C:\Program Files\Enterprise Apps\Current Version"
$BINARY_PATH  = "C:\Program Files\Enterprise Apps\Current Version\GammaService.exe"
$VULN_DIR     = "C:\Program Files\Enterprise Apps"
$STUDENT_USER = "dave"
$STUDENT_PASS = "lab"

Write-Host "`n[*] Starting lab setup: Unquoted Service Path`n" -ForegroundColor Cyan

# 1. Create student account
Write-Host "[*] Creating user '$STUDENT_USER'..."
$secPass = ConvertTo-SecureString $STUDENT_PASS -AsPlainText -Force

if (Get-LocalUser -Name $STUDENT_USER -ErrorAction SilentlyContinue) {
    Write-Host "    User '$STUDENT_USER' already exists - skipping."
} else {
    New-LocalUser -Name $STUDENT_USER `
                  -Password $secPass `
                  -FullName "Lab Student" `
                  -Description "Low-privilege lab account" `
                  -PasswordNeverExpires | Out-Null
    Add-LocalGroupMember -Group "Users" -Member $STUDENT_USER
    Write-Host "    [+] User '$STUDENT_USER' created (password: $STUDENT_PASS)" -ForegroundColor Green
}

# 2. Create full directory structure
Write-Host "[*] Creating directory structure: $BINARY_DIR"
New-Item -ItemType Directory -Path $BINARY_DIR -Force | Out-Null
Write-Host "    [+] Directories created." -ForegroundColor Green

# 3. Compile minimal Windows service binary as GammaService.exe
Write-Host "[*] Compiling placeholder GammaService.exe (minimal Windows service)..."

$svcSource = @'
using System;
using System.ServiceProcess;
using System.Threading;

public class GammaService : ServiceBase {
    private Thread _worker;
    private bool _running;

    public GammaService() { ServiceName = "GammaSvc"; }

    protected override void OnStart(string[] args) {
        _running = true;
        _worker = new Thread(() => { while (_running) Thread.Sleep(500); });
        _worker.Start();
    }

    protected override void OnStop() {
        _running = false;
        if (_worker != null) _worker.Join(3000);
    }

    static void Main() {
        ServiceBase.Run(new GammaService());
    }
}
'@

# Stop and delete existing service first to release file lock on binary
if (Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue) {
    sc.exe stop $SERVICE_NAME 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    sc.exe delete $SERVICE_NAME | Out-Null
    Start-Sleep -Seconds 1
}
if (Test-Path $BINARY_PATH) { Remove-Item $BINARY_PATH -Force }

# csc.exe produces proper WinExe that SCM can register — Add-Type sometimes misses the handshake window
$tempCs = [System.IO.Path]::GetTempPath() + "GammaServiceSrc.cs"
$svcSource | Set-Content $tempCs -Encoding UTF8
$cscPath = (Get-ChildItem "$env:SystemRoot\Microsoft.NET\Framework64" -Filter "csc.exe" -Recurse `
            -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1).FullName
if (-not $cscPath) { throw "csc.exe not found - install .NET Framework 4.x." }
$svcDll = Join-Path ([System.IO.Path]::GetDirectoryName($cscPath)) "System.ServiceProcess.dll"
& $cscPath /nologo /target:winexe /out:"$BINARY_PATH" /reference:"$svcDll" $tempCs 2>&1 | Out-Null
Remove-Item $tempCs -Force -ErrorAction SilentlyContinue

Write-Host "    [+] GammaService.exe compiled at $BINARY_PATH" -ForegroundColor Green

# 4. Create service with UNQUOTED binary path (no surrounding quotes in registry)
Write-Host "[*] Creating service '$SERVICE_NAME' with unquoted binary path..."

if (Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue) {
    Write-Host "    Service already exists - removing old instance..."
    Stop-Service -Name $SERVICE_NAME -Force -ErrorAction SilentlyContinue
    sc.exe delete $SERVICE_NAME | Out-Null
    Start-Sleep -Seconds 1
}

# Intentionally unquoted: PowerShell string delimiters are stripped — registry gets bare path with spaces
sc.exe create $SERVICE_NAME `
    binPath= "$BINARY_PATH" `
    DisplayName= $SERVICE_DISP `
    start= auto `
    obj= LocalSystem | Out-Null

Write-Host "    [+] Service created (LocalSystem, Automatic start, unquoted path)." -ForegroundColor Green

# 5. Grant dave SERVICE_START (RP) and SERVICE_STOP (WP) on the service object
Write-Host "[*] Granting dave start/stop permissions on service..."
$daveSid = (New-Object System.Security.Principal.NTAccount($STUDENT_USER)).Translate(
               [System.Security.Principal.SecurityIdentifier]).Value
$currentSddl = (sc.exe sdshow $SERVICE_NAME | Where-Object { $_ -match 'D:' }).Trim()
$newSddl = $currentSddl -replace '(D:[^(]*)', "`$1(A;;RPWP;;;$daveSid)"
sc.exe sdset $SERVICE_NAME $newSddl | Out-Null
Write-Host "    [+] dave can now start/stop GammaSvc." -ForegroundColor Green

# 6. Set vulnerable ACL — Modify on the intermediate directory, not the binary
# dave can create files here (e.g. Current.exe) but cannot touch the real binary
Write-Host "[*] Setting vulnerable ACL on intermediate directory..."
icacls $VULN_DIR /grant "${STUDENT_USER}:(M)" | Out-Null
Write-Host "    [+] ACL set: $STUDENT_USER has (M) on $VULN_DIR" -ForegroundColor Green

# 6. Start service (may fail — .NET inline binary may not register cleanly with SCM)
# This is expected and does not affect the lab. Student triggers exploit via sc.exe start.
Write-Host "[*] Starting service (failure here is expected and harmless)..."
sc.exe start $SERVICE_NAME 2>&1 | Out-Null
$svcState = (sc.exe query $SERVICE_NAME | Select-String "STATE").ToString().Trim()
Write-Host "    [*] Service state: $svcState" -ForegroundColor Yellow

# 7. Verification output
Write-Host "`n[+] Lab setup complete. Verification:`n" -ForegroundColor Cyan

Write-Host "--- Service config (check BINARY_PATH_NAME has no quotes) ---"
sc.exe qc $SERVICE_NAME

Write-Host "`n--- Intermediate directory ACL ---"
icacls $VULN_DIR

Write-Host "`n--- Student account ---"
Get-LocalUser -Name $STUDENT_USER | Select-Object Name, Enabled, PasswordRequired | Format-List

Write-Host "`n[*] Hand the machine to '$STUDENT_USER' (password: $STUDENT_PASS)." -ForegroundColor Cyan
Write-Host "[*] Student goal: enumerate unquoted paths, verify write access on intermediate dir,"
Write-Host "[*]   drop a payload as 'Current.exe' in '$VULN_DIR', restart service, gain SYSTEM.`n"
