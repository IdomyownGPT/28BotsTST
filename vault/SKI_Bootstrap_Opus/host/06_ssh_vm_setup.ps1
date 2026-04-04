<#
.SYNOPSIS
    SKI Bootstrap — Step 6: Run VM setup scripts remotely via SSH
.DESCRIPTION
    Connects to the Ubuntu VM via SSH and runs the bootstrap scripts in order.
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

# Run scripts
$scripts = @(
    @{ Name = "01_setup_base.sh";        Desc = "Base packages & system config" },
    @{ Name = "02_setup_smb_mount.sh";   Desc = "SMB mount configuration" },
    @{ Name = "03_setup_docker.sh";      Desc = "Docker installation" }
)

Write-Host "`n  Running VM setup scripts..." -ForegroundColor Cyan
Write-Host "  (04_deploy_containers.sh and 05_setup_hermes.sh require manual run after Docker group reload)`n" -ForegroundColor Yellow

foreach ($script in $scripts) {
    Write-Host "  ┌─ $($script.Name): $($script.Desc)" -ForegroundColor Cyan
    $result = ssh "$VM_USER@$VM_IP" "sudo bash $BOOTSTRAP_PATH/$($script.Name)" 2>&1
    Write-Host $result
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  └─ [DONE]" -ForegroundColor Green
    } else {
        Write-Host "  └─ [FAILED] Exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  Stopping. Fix the issue and re-run." -ForegroundColor Yellow
        exit 1
    }
    Write-Host ""
}

Write-Host "`n[DONE] Base VM setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "  REMAINING MANUAL STEPS:" -ForegroundColor Yellow
Write-Host "    1. SSH into VM: ssh $VM_USER@$VM_IP" -ForegroundColor Gray
Write-Host "    2. Log out and back in (for Docker group)" -ForegroundColor Gray
Write-Host "    3. Run: bash $BOOTSTRAP_PATH/04_deploy_containers.sh" -ForegroundColor Gray
Write-Host "    4. Run: bash $BOOTSTRAP_PATH/05_setup_hermes.sh" -ForegroundColor Gray
Write-Host "    5. Run: bash $BOOTSTRAP_PATH/06_verify_vm.sh" -ForegroundColor Gray
