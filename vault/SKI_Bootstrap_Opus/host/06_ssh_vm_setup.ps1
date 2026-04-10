<#
.SYNOPSIS
    SKI Bootstrap — Step 6: Run VM setup scripts remotely via SSH
.DESCRIPTION
    Connects to the Ubuntu VM via SSH and runs the master installer interactively.
    Uses ssh -t for TTY allocation so interactive prompts work through SSH.
    Uses sg docker to avoid logout/login after Docker group setup.
    Requires: OpenSSH client on Host, OpenSSH server on VM.
#>

$ErrorActionPreference = "Stop"

Write-Host "`n=== SKI Bootstrap: Remote VM Setup via SSH ===" -ForegroundColor Cyan

$VM_IP = "192.168.178.124"
$VM_USER = "archat"
$BOOTSTRAP_PATH = "/mnt/28bots_core/Obsidian_Vault/SKI_Bootstrap_Opus/vm"

# Check SSH availability
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "  [FAIL] SSH client not found." -ForegroundColor Red
    Write-Host "  Install: Settings > Apps > Optional Features > OpenSSH Client" -ForegroundColor Yellow
    exit 1
}

# Test SSH connectivity
Write-Host "`n  Testing SSH connection to $VM_USER@$VM_IP..." -ForegroundColor Cyan
$testResult = ssh -o ConnectTimeout=5 -o BatchMode=yes "$VM_USER@$VM_IP" "echo SSH_OK" 2>&1
if ($testResult -match "SSH_OK") {
    Write-Host "  [OK] SSH connection successful" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Cannot connect via SSH to $VM_USER@$VM_IP" -ForegroundColor Red
    Write-Host "  Ensure:" -ForegroundColor Yellow
    Write-Host "    1. VM is running" -ForegroundColor Gray
    Write-Host "    2. OpenSSH server installed on VM: sudo apt install openssh-server" -ForegroundColor Gray
    Write-Host "    3. SSH key or password auth is configured" -ForegroundColor Gray
    exit 1
}

# Check if bootstrap scripts exist on VM
Write-Host "`n  Checking bootstrap scripts on VM..." -ForegroundColor Cyan
$scriptCheck = ssh "$VM_USER@$VM_IP" "ls $BOOTSTRAP_PATH/*.sh 2>/dev/null | wc -l"
if ([int]$scriptCheck -lt 1) {
    Write-Host "  [FAIL] No scripts found at $BOOTSTRAP_PATH" -ForegroundColor Red
    Write-Host "  Ensure the Vault SMB mount is active on the VM." -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Found $scriptCheck scripts" -ForegroundColor Green

# Make scripts executable
ssh "$VM_USER@$VM_IP" "chmod +x $BOOTSTRAP_PATH/*.sh"

# Run master installer with TTY allocation for interactive prompts
Write-Host "`n  Running master installer on VM..." -ForegroundColor Cyan
Write-Host "  NOTE: Scripts are interactive — answer prompts in the terminal." -ForegroundColor Yellow
Write-Host ""

ssh -t "$VM_USER@$VM_IP" "bash $BOOTSTRAP_PATH/install_ski_vm.sh"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n  [DONE] VM setup complete!" -ForegroundColor Green
} else {
    Write-Host "`n  [WARN] Master installer exited with code $LASTEXITCODE" -ForegroundColor Yellow
    Write-Host "  Check the output above for details." -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Tip: Run 06_verify_vm.sh on the VM to confirm everything works." -ForegroundColor Gray
Write-Host ""
