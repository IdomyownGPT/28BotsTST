#Requires -RunAsAdministrator
<#
.SYNOPSIS
    SKI Bootstrap — Step 5: Verify Host setup
.DESCRIPTION
    Checks all host-side prerequisites: directories, SMB share, firewall, VM, LM Studio.
#>

$ErrorActionPreference = "Continue"

Write-Host "`n=== SKI Bootstrap: Host Verification ===" -ForegroundColor Cyan

$pass = 0; $fail = 0; $warn = 0

function Check-Pass($msg) { $script:pass++; Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Check-Fail($msg) { $script:fail++; Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Check-Warn($msg) { $script:warn++; Write-Host "  [WARN] $msg" -ForegroundColor Yellow }

# ── Directories ──
Write-Host "`n--- Directories ---" -ForegroundColor Cyan
$dirs = @(
    "D:\28Bots_Core\Obsidian_Vault\root",
    "D:\28Bots_Core\Obsidian_Vault\root\SKI_Cookbook",
    "D:\28Bots_Core\Obsidian_Vault\root\SKI_Bootstrap",
    "D:\28Bots_Core\Obsidian_Vault\root\SKI_Pilot",
    "D:\28Bots\Models\LLM_LIB"
)
foreach ($dir in $dirs) {
    if (Test-Path $dir) { Check-Pass $dir } else { Check-Fail "$dir not found" }
}

# ── SMB Share ──
Write-Host "`n--- SMB Share ---" -ForegroundColor Cyan
$share = Get-SmbShare -Name "SKI-Vault-Root" -ErrorAction SilentlyContinue
if ($share) {
    Check-Pass "SMB share 'SKI-Vault-Root' exists at $($share.Path)"
} else {
    Check-Fail "SMB share 'SKI-Vault-Root' not found"
}

$user = Get-LocalUser -Name "skiuser" -ErrorAction SilentlyContinue
if ($user) { Check-Pass "User 'skiuser' exists" } else { Check-Fail "User 'skiuser' not found" }

# ── Firewall ──
Write-Host "`n--- Firewall Rules ---" -ForegroundColor Cyan
foreach ($ruleName in @("SKI-LMStudio-API", "SKI-SMB-Vault")) {
    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($rule -and $rule.Enabled -eq "True") {
        Check-Pass "Firewall rule '$ruleName' is active"
    } elseif ($rule) {
        Check-Warn "Firewall rule '$ruleName' exists but is disabled"
    } else {
        Check-Fail "Firewall rule '$ruleName' not found"
    }
}

# ── Hyper-V VM ──
Write-Host "`n--- Hyper-V VM ---" -ForegroundColor Cyan
$vm = Get-VM -Name "28Bots-Orchestrator-GUI" -ErrorAction SilentlyContinue
if ($vm) {
    Check-Pass "VM '28Bots-Orchestrator-GUI' exists (State: $($vm.State))"
    if ($vm.State -eq "Running") {
        Check-Pass "VM is running"
    } else {
        Check-Warn "VM is not running (State: $($vm.State))"
    }
    $ramGB = [math]::Round($vm.MemoryAssigned / 1GB, 1)
    if ($ramGB -ge 16) {
        Check-Pass "VM RAM: ${ramGB}GB"
    } elseif ($ramGB -ge 9) {
        Check-Warn "VM RAM: ${ramGB}GB (16GB recommended)"
    } else {
        Check-Fail "VM RAM: ${ramGB}GB (minimum 9GB required)"
    }
} else {
    Check-Fail "VM '28Bots-Orchestrator-GUI' not found"
}

# ── LM Studio ──
Write-Host "`n--- LM Studio ---" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "http://localhost:1234/v1/models" -TimeoutSec 5 -ErrorAction Stop
    Check-Pass "LM Studio API responding on :1234"
    $modelCount = $response.data.Count
    Write-Host "    Models loaded: $modelCount" -ForegroundColor Gray
    foreach ($model in $response.data) {
        Write-Host "    - $($model.id)" -ForegroundColor Gray
    }
} catch {
    Check-Fail "LM Studio API not responding on :1234"
}

# ── Network ──
Write-Host "`n--- Network ---" -ForegroundColor Cyan
$vmIP = "192.168.178.124"
if (Test-Connection -ComputerName $vmIP -Count 1 -Quiet) {
    Check-Pass "VM reachable at $vmIP"
} else {
    Check-Warn "VM not reachable at $vmIP (may be off)"
}

# ── Summary ──
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  PASS: $pass" -ForegroundColor Green
if ($fail -gt 0) { Write-Host "  FAIL: $fail" -ForegroundColor Red }
if ($warn -gt 0) { Write-Host "  WARN: $warn" -ForegroundColor Yellow }
$total = $pass + $fail + $warn
Write-Host "  Total: $total checks" -ForegroundColor Gray

if ($fail -gt 0) {
    Write-Host "`n  Result: FAILURES DETECTED" -ForegroundColor Red
    exit 1
} elseif ($warn -gt 0) {
    Write-Host "`n  Result: WARNINGS (review recommended)" -ForegroundColor Yellow
} else {
    Write-Host "`n  Result: ALL PASSED" -ForegroundColor Green
}
