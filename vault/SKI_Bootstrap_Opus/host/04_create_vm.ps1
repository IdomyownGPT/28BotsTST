#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SKI Bootstrap — Step 4: Create Hyper-V VM
.DESCRIPTION
    Creates the 28Bots-Orchestrator-GUI VM with recommended specs.
    SKIP this script if the VM already exists.
#>

$ErrorActionPreference = "Stop"

Write-Host "`n=== SKI Bootstrap: Hyper-V VM Creation ===" -ForegroundColor Cyan

$VMName = "28Bots-Orchestrator-GUI"
$VMPath = "D:\VMs\VM_HDDs"
$VHDPath = "$VMPath\$VMName.vhdx"
$SwitchName = "Default Switch"
$RAM = 16GB
$VHDSize = 120GB
$CPUCount = 4

# Check if VM already exists
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "  [OK] VM '$VMName' already exists (State: $($existingVM.State))" -ForegroundColor Green
    Write-Host "  Skipping creation. Delete the VM first if you want to recreate." -ForegroundColor Yellow
    exit 0
}

# Check for Hyper-V
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    Write-Host "  [FAIL] Hyper-V is not installed or not available" -ForegroundColor Red
    Write-Host "  Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -ForegroundColor Yellow
    exit 1
}

# List available switches
Write-Host "`n  Available Virtual Switches:" -ForegroundColor Cyan
Get-VMSwitch | Format-Table Name, SwitchType -AutoSize

$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $switch) {
    Write-Host "  [WARN] Switch '$SwitchName' not found. Using first external switch..." -ForegroundColor Yellow
    $switch = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
    if (-not $switch) {
        Write-Host "  [FAIL] No external switch found. Create one in Hyper-V Manager first." -ForegroundColor Red
        exit 1
    }
    $SwitchName = $switch.Name
    Write-Host "  Using switch: $SwitchName" -ForegroundColor Cyan
}

# Create VM
Write-Host "`n  Creating VM '$VMName'..." -ForegroundColor Yellow
Write-Host "    RAM:    $($RAM / 1GB) GB" -ForegroundColor Gray
Write-Host "    CPU:    $CPUCount vCPUs" -ForegroundColor Gray
Write-Host "    Disk:   $($VHDSize / 1GB) GB" -ForegroundColor Gray
Write-Host "    Switch: $SwitchName" -ForegroundColor Gray

New-VM -Name $VMName `
    -Generation 2 `
    -MemoryStartupBytes $RAM `
    -Path $VMPath `
    -NewVHDPath $VHDPath `
    -NewVHDSizeBytes $VHDSize `
    -SwitchName $SwitchName | Out-Null

# Configure VM
Set-VM -Name $VMName `
    -ProcessorCount $CPUCount `
    -DynamicMemory `
    -MemoryMinimumBytes 4GB `
    -MemoryMaximumBytes $RAM `
    -AutomaticStartAction Start `
    -AutomaticStopAction ShutDown

# Disable Secure Boot for Ubuntu
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off

Write-Host "`n  [CREATED] VM '$VMName'" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "    1. Mount Ubuntu 24.04 ISO in Hyper-V Manager" -ForegroundColor Gray
Write-Host "    2. Start VM and install Ubuntu" -ForegroundColor Gray
Write-Host "    3. Set user: archat, hostname: 28bots-orchestrator" -ForegroundColor Gray
Write-Host "    4. Set static IP: 192.168.178.124" -ForegroundColor Gray
Write-Host "    5. Install OpenSSH: sudo apt install openssh-server" -ForegroundColor Gray
Write-Host "    6. Then run: 06_ssh_vm_setup.ps1" -ForegroundColor Gray
