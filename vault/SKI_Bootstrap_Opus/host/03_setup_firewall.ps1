#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SKI Bootstrap — Step 3: Configure Windows Firewall rules
.DESCRIPTION
    Opens required ports for LM Studio API and SMB access from the VM.
#>

$ErrorActionPreference = "Stop"

Write-Host "`n=== SKI Bootstrap: Firewall Setup ===" -ForegroundColor Cyan

$VM_IP = "192.168.178.124"

$rules = @(
    @{
        Name        = "SKI-LMStudio-API"
        DisplayName = "SKI: LM Studio API (TCP 1234)"
        Port        = "1234"
        Description = "Allow LM Studio API access from VM"
    },
    @{
        Name        = "SKI-SMB-Vault"
        DisplayName = "SKI: SMB Vault Access (TCP 445)"
        Port        = "445"
        Description = "Allow SMB access to Obsidian Vault from VM"
    },
    @{
        Name        = "SKI-SSH-Inbound"
        DisplayName = "SKI: SSH Inbound (TCP 22)"
        Port        = "22"
        Description = "Allow SSH access (if OpenSSH server is installed)"
    }
)

foreach ($rule in $rules) {
    $existing = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [OK] Rule '$($rule.DisplayName)' exists" -ForegroundColor Green
    } else {
        New-NetFirewallRule `
            -Name $rule.Name `
            -DisplayName $rule.DisplayName `
            -Description $rule.Description `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $rule.Port `
            -RemoteAddress $VM_IP `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "  [CREATED] $($rule.DisplayName) (from $VM_IP)" -ForegroundColor Yellow
    }
}

# Verify
Write-Host "`n  Active SKI Firewall Rules:" -ForegroundColor Cyan
Get-NetFirewallRule -Name "SKI-*" | Format-Table Name, DisplayName, Enabled, Direction -AutoSize

Write-Host "`n[DONE] Firewall rules configured." -ForegroundColor Green
Write-Host "Next: Run 04_create_vm.ps1 (if VM doesn't exist yet)" -ForegroundColor Cyan
