#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Lab setup: Service Binary Hijacking (XAMPP Apache scenario)
    Creates vulnerable environment where user 'dave' can replace httpd.exe

.NOTES
    Run as Administrator before handing machine to student (dave)
#>

$ErrorActionPreference = "Stop"

$SERVICE_NAME  = "Apache2.4"
$SERVICE_DISP  = "Apache HTTP Server 2.4"
$BINARY_DIR    = "C:\xampp\apache\bin"
$BINARY_PATH   = "$BINARY_DIR\httpd.exe"
$STUDENT_USER  = "dave"
$STUDENT_PASS  = "lab"

Write-Host "`n[*] Starting lab setup: Service Binary Hijacking`n" -ForegroundColor Cyan

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

# 2. Create XAMPP directory structure
Write-Host "[*] Creating directory structure: $BINARY_DIR"
New-Item -ItemType Directory -Path $BINARY_DIR -Force | Out-Null
Write-Host "    [+] Directory created." -ForegroundColor Green

# 3. Compile minimal Windows service binary as httpd.exe
Write-Host "[*] Compiling placeholder httpd.exe (minimal Windows service)..."

$svcSource = @'
using System;
using System.ServiceProcess;
using System.Threading;

public class HttpdService : ServiceBase {
    private Thread _worker;
    private bool _running;

    public HttpdService() { ServiceName = "Apache2.4"; }

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
        ServiceBase.Run(new HttpdService());
    }
}
'@

if (Test-Path $BINARY_PATH) { Remove-Item $BINARY_PATH -Force }

Add-Type -TypeDefinition $svcSource `
         -ReferencedAssemblies "System.ServiceProcess" `
         -OutputAssembly $BINARY_PATH `
         -OutputType WindowsApplication

Write-Host "    [+] httpd.exe compiled at $BINARY_PATH" -ForegroundColor Green

# 4. Create vulnerable service
Write-Host "[*] Creating service '$SERVICE_NAME'..."

if (Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue) {
    Write-Host "    Service already exists - removing old instance..."
    Stop-Service -Name $SERVICE_NAME -Force -ErrorAction SilentlyContinue
    sc.exe delete $SERVICE_NAME | Out-Null
    Start-Sleep -Seconds 1
}

sc.exe create $SERVICE_NAME `
    binPath= "`"$BINARY_PATH`"" `
    DisplayName= $SERVICE_DISP `
    start= auto `
    obj= LocalSystem | Out-Null

Write-Host "    [+] Service created (LocalSystem, Automatic start)." -ForegroundColor Green

# 5. Set vulnerable ACL on httpd.exe
# Grant dave WRITE only - realistic misconfiguration, not FullControl
Write-Host "[*] Setting vulnerable ACL on httpd.exe..."
icacls $BINARY_PATH /grant "${STUDENT_USER}:(W)" | Out-Null
Write-Host "    [+] ACL set: $STUDENT_USER has (W) on httpd.exe" -ForegroundColor Green

# 6. Start service
Write-Host "[*] Starting service..."
# cmd.exe will fail as service binary - expected. SCM record + auto-start is what matters.
sc.exe start $SERVICE_NAME 2>&1 | Out-Null
Write-Host "    [+] Service start attempted (may show FAILED - expected for cmd.exe placeholder)." -ForegroundColor Yellow

# 7. Verification output
Write-Host "`n[+] Lab setup complete. Verification:`n" -ForegroundColor Cyan

Write-Host "--- Service config ---"
sc.exe qc $SERVICE_NAME

Write-Host "`n--- File ACL on httpd.exe ---"
icacls $BINARY_PATH

Write-Host "`n--- Student account ---"
Get-LocalUser -Name $STUDENT_USER | Select-Object Name, Enabled, PasswordRequired | Format-List

Write-Host "`n[*] Hand the machine to '$STUDENT_USER' (password: $STUDENT_PASS)." -ForegroundColor Cyan
Write-Host "[*] Student goal: replace httpd.exe, reboot, gain SYSTEM execution.`n"
