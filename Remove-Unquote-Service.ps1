#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Lab cleanup: removes Unquoted Service Path lab environment

.NOTES
    Run as Administrator after lab session ends
#>

$ErrorActionPreference = "SilentlyContinue"

$SERVICE_NAME = "GammaSvc"
$ENTERPRISE_ROOT = "C:\Program Files\Enterprise Apps"
$STUDENT_USER = "dave"
$ADMIN_GROUP  = "Administrators"

Write-Host "`n[*] Starting lab cleanup`n" -ForegroundColor Cyan

# ── 1. Stop and delete service ───────────────────────────────────────────────
Write-Host "[*] Stopping and removing service '$SERVICE_NAME'..."
$svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service -Name $SERVICE_NAME -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    sc.exe delete $SERVICE_NAME | Out-Null
    Write-Host "    [+] Service removed." -ForegroundColor Green
} else {
    Write-Host "    Service not found - skipping."
}

# ── 2. Remove Galax Systems directory ────────────────────────────────────────
Write-Host "[*] Removing $ENTERPRISE_ROOT..."
if (Test-Path $ENTERPRISE_ROOT) {
    Remove-Item -Path $ENTERPRISE_ROOT -Recurse -Force
    Write-Host "    [+] Directory removed." -ForegroundColor Green
} else {
    Write-Host "    Directory not found - skipping."
}

# ── 3. Remove dave from Administrators if exploit succeeded ──────────────────
Write-Host "[*] Checking if '$STUDENT_USER' is in Administrators group..."
$isAdmin = Get-LocalGroupMember -Group $ADMIN_GROUP -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like "*$STUDENT_USER*" }

if ($isAdmin) {
    Remove-LocalGroupMember -Group $ADMIN_GROUP -Member $STUDENT_USER -ErrorAction SilentlyContinue
    Write-Host "    [+] '$STUDENT_USER' removed from Administrators." -ForegroundColor Green
} else {
    Write-Host "    '$STUDENT_USER' not in Administrators - no action needed."
}

# ── 4. (Optional) Delete student account entirely ────────────────────────────
# Uncomment to fully remove dave after lab
# Write-Host "[*] Deleting user '$STUDENT_USER'..."
# Remove-LocalUser -Name $STUDENT_USER -ErrorAction SilentlyContinue
# Write-Host "    [+] User '$STUDENT_USER' deleted." -ForegroundColor Green

# ── 5. Verify cleanup ────────────────────────────────────────────────────────
Write-Host "`n[+] Cleanup complete. Verification:`n" -ForegroundColor Cyan

$svcCheck = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
$dirCheck = Test-Path $ENTERPRISE_ROOT
$admCheck = Get-LocalGroupMember -Group $ADMIN_GROUP -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$STUDENT_USER*" }

Write-Host "--- Results ---"
if (-not $svcCheck) { Write-Host "Service '$SERVICE_NAME' removed : YES" -ForegroundColor Green }
else                { Write-Host "Service '$SERVICE_NAME' removed : NO - check manually" -ForegroundColor Red }
if (-not $dirCheck) { Write-Host "Directory $ENTERPRISE_ROOT removed  : YES" -ForegroundColor Green }
else                { Write-Host "Directory $ENTERPRISE_ROOT removed  : NO - check manually" -ForegroundColor Red }
if (-not $admCheck) { Write-Host "dave removed from Admins       : YES / was not member" -ForegroundColor Green }
else                { Write-Host "dave removed from Admins       : NO - check manually" -ForegroundColor Red }
Write-Host ""
