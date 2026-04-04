#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SKI Bootstrap — Step 2: Create SMB share for Obsidian Vault
.DESCRIPTION
    Creates the SMB share "SKI-Vault-Root" pointing to the Obsidian Vault root.
    Creates the skiuser local account if it doesn't exist.
#>

$ErrorActionPreference = "Stop"

Write-Host "`n=== SKI Bootstrap: SMB Share Setup ===" -ForegroundColor Cyan

$ShareName = "SKI-Vault-Root"
$SharePath = "D:\28Bots_Core\Obsidian_Vault\root"
$UserName = "skiuser"

# Check share path exists
if (-not (Test-Path $SharePath)) {
    Write-Host "  [FAIL] Share path does not exist: $SharePath" -ForegroundColor Red
    Write-Host "  Run 01_setup_directories.ps1 first." -ForegroundColor Yellow
    exit 1
}

# Create skiuser if not exists
$user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Host "  Creating local user '$UserName'..." -ForegroundColor Yellow
    $password = Read-Host "  Enter password for $UserName" -AsSecureString
    New-LocalUser -Name $UserName -Password $password -Description "SKI Vault SMB User" -PasswordNeverExpires
    Write-Host "  [CREATED] User '$UserName'" -ForegroundColor Green
} else {
    Write-Host "  [OK] User '$UserName' exists" -ForegroundColor Green
}

# Create or update SMB share
$share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if ($share) {
    Write-Host "  [OK] Share '$ShareName' already exists at $($share.Path)" -ForegroundColor Green
} else {
    New-SmbShare -Name $ShareName -Path $SharePath -FullAccess $UserName -Description "SKI Obsidian Vault Root"
    Write-Host "  [CREATED] Share '$ShareName' -> $SharePath" -ForegroundColor Green
}

# Set NTFS permissions
$acl = Get-Acl $SharePath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserName, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($rule)
Set-Acl $SharePath $acl
Write-Host "  [OK] NTFS permissions set for '$UserName' on $SharePath" -ForegroundColor Green

# Verify
Write-Host "`n  Verification:" -ForegroundColor Cyan
Get-SmbShare -Name $ShareName | Format-Table Name, Path, Description -AutoSize

Write-Host "[DONE] SMB share configured." -ForegroundColor Green
Write-Host "Next: Run 03_setup_firewall.ps1" -ForegroundColor Cyan
