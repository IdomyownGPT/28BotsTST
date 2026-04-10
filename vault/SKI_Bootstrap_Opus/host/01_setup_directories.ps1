#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SKI Bootstrap — Step 1: Create directory structure on Host
.DESCRIPTION
    Creates the required folder structure on D:\ for the SKI system.
#>

$ErrorActionPreference = "Stop"

Write-Host "`n=== SKI Bootstrap: Directory Setup ===" -ForegroundColor Cyan

$directories = @(
    "D:\28Bots_Core",
    "D:\28Bots_Core\Obsidian_Vault",
    "D:\28Bots_Core\Obsidian_Vault\root",
    "D:\28Bots_Core\Obsidian_Vault\root\SKI_Cookbook",
    "D:\28Bots_Core\Obsidian_Vault\root\SKI_Bootstrap",
    "D:\28Bots_Core\Obsidian_Vault\root\SKI_Pilot",
    "D:\28Bots_Core\VectorDB_Hindsight",
    "D:\28Bots\Models\LLM_LIB",
    "D:\VMs\VM_HDDs"
)

foreach ($dir in $directories) {
    if (Test-Path $dir) {
        Write-Host "  [OK] $dir (exists)" -ForegroundColor Green
    } else {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  [CREATED] $dir" -ForegroundColor Yellow
    }
}

# Create Cookbook module directories M00-M11
for ($i = 0; $i -le 11; $i++) {
    $module = "D:\28Bots_Core\Obsidian_Vault\root\SKI_Cookbook\M{0:D2}" -f $i
    if (-not (Test-Path $module)) {
        New-Item -ItemType Directory -Path $module -Force | Out-Null
        Write-Host "  [CREATED] $module" -ForegroundColor Yellow
    }
}

Write-Host "`n[DONE] Directory structure created." -ForegroundColor Green
Write-Host "Next: Run 02_setup_smb_share.ps1" -ForegroundColor Cyan
