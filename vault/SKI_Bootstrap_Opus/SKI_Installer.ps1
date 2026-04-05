#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    SKI Installer — Sephirotische Kernintelligenz — Windows Server 2025
.DESCRIPTION
    Unified installer and sanity checker for the SKI host environment.
    Does NOT install new software. Configures directories, SMB, firewall, and Hyper-V VM.
.PARAMETER Mode
    Run mode: Menu (default), FullInstall, SanityCheck, Step1-Step4, RemoteSetup
.PARAMETER HostIP
    Host IP address (default: 192.168.178.90)
.PARAMETER VMIP
    VM IP address (default: 192.168.178.124)
.EXAMPLE
    .\SKI_Installer.ps1
    .\SKI_Installer.ps1 -Mode SanityCheck
    .\SKI_Installer.ps1 -Mode FullInstall -VMIP 10.0.0.5
#>
[CmdletBinding()]
param(
    [ValidateSet("Menu","FullInstall","SanityCheck","Step1","Step2","Step3","Step4","Step5","RemoteSetup")]
    [string]$Mode          = "Menu",
    [string]$HostIP        = "192.168.178.90",
    [string]$VMIP          = "192.168.178.124",
    [string]$VMUser        = "archat",
    [string]$ShareName     = "SKI-Vault-Root",
    [string]$SMBUser       = "skiuser",
    [int]$LMStudioPort     = 1234,
    [string]$VaultPath     = "D:\28Bots_Core\Obsidian_Vault\root",
    [string]$VMName        = "28Bots-Orchestrator-GUI",
    [string]$BootstrapPath = "/mnt/28bots_core/Obsidian_Vault/SKI_Bootstrap_Opus/vm",
    [string]$AutoResearchDir = "D:\28Bots_Core\AutoResearch",
    [string]$AutoResearchModel = "bonsai-prism-8b"
)

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════

$Config = @{
    HostIP        = $HostIP
    VMIP          = $VMIP
    VMUser        = $VMUser
    ShareName     = $ShareName
    SMBUser       = $SMBUser
    LMStudioPort  = $LMStudioPort
    VaultPath     = $VaultPath
    VMName        = $VMName
    VMPath        = "D:\VMs\VM_HDDs"
    RAM           = 16GB
    VHDSize       = 120GB
    CPUCount      = 4
    BootstrapPath = $BootstrapPath
    AutoResearchDir = $AutoResearchDir
    AutoResearchModel = $AutoResearchModel
}

# ═══════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════

$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0

function Write-Banner($title) {
    Write-Host "`n===  $title  ===" -ForegroundColor Cyan
}

function Write-Pass($msg)    { $script:PassCount++; Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Write-Fail($msg)    { $script:FailCount++; Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Warn($msg)    { $script:WarnCount++; Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-OK($msg)      { Write-Host "  [OK]      $msg" -ForegroundColor Green }
function Write-Created($msg) { Write-Host "  [CREATED] $msg" -ForegroundColor Yellow }
function Write-Info($msg)    { Write-Host "  [INFO]    $msg" -ForegroundColor Gray }

function Reset-Counters {
    $script:PassCount = 0; $script:FailCount = 0; $script:WarnCount = 0
}

function Show-Summary($label) {
    Write-Host "`n--- $label Summary ---" -ForegroundColor Cyan
    Write-Host "  PASS: $script:PassCount" -ForegroundColor Green
    if ($script:FailCount -gt 0) { Write-Host "  FAIL: $script:FailCount" -ForegroundColor Red }
    if ($script:WarnCount -gt 0) { Write-Host "  WARN: $script:WarnCount" -ForegroundColor Yellow }
    $total = $script:PassCount + $script:FailCount + $script:WarnCount
    Write-Host "  Total: $total checks" -ForegroundColor Gray
    if ($script:FailCount -gt 0) {
        Write-Host "`n  Result: FAILURES DETECTED" -ForegroundColor Red
        return $false
    } elseif ($script:WarnCount -gt 0) {
        Write-Host "`n  Result: WARNINGS (review recommended)" -ForegroundColor Yellow
        return $true
    } else {
        Write-Host "`n  Result: ALL PASSED" -ForegroundColor Green
        return $true
    }
}

function Confirm-Proceed($action) {
    $answer = Read-Host "  $action [Y/n]"
    return ($answer -eq '' -or $answer -match '^[Yy]')
}

function Show-Config {
    Write-Banner "Current Configuration"
    foreach ($key in ($Config.Keys | Sort-Object)) {
        $val = $Config[$key]
        if ($val -is [long] -or $val -is [int64]) {
            $val = "$([math]::Round($val / 1GB, 0)) GB"
        }
        Write-Host ("  {0,-16} = {1}" -f $key, $val) -ForegroundColor Gray
    }
}

# ═══════════════════════════════════════════════════════════════
# Step 1: Directory Structure
# ═══════════════════════════════════════════════════════════════

function Install-Directories {
    Write-Banner "Step 1: Directory Structure"

    $dirs = @(
        "D:\28Bots_Core",
        "D:\28Bots_Core\Obsidian_Vault",
        $Config.VaultPath,
        "$($Config.VaultPath)\SKI_Cookbook",
        "$($Config.VaultPath)\SKI_Bootstrap",
        "$($Config.VaultPath)\SKI_Bootstrap_Opus",
        "$($Config.VaultPath)\SKI_Pilot",
        "D:\28Bots_Core\VectorDB_Hindsight",
        "D:\28Bots\Models\LLM_LIB",
        $Config.VMPath
    )

    foreach ($dir in $dirs) {
        if (Test-Path $dir) {
            Write-OK "$dir"
        } else {
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Created "$dir"
            } catch {
                Write-Host "  [ERROR] Failed to create $dir : $_" -ForegroundColor Red
                return $false
            }
        }
    }

    # M00-M11 cookbook modules
    for ($i = 0; $i -le 11; $i++) {
        $module = "$($Config.VaultPath)\SKI_Cookbook\M{0:D2}" -f $i
        if (-not (Test-Path $module)) {
            New-Item -ItemType Directory -Path $module -Force | Out-Null
            Write-Created $module
        }
    }

    Write-Host "`n  [DONE] Directory structure ready." -ForegroundColor Green
    return $true
}

# ═══════════════════════════════════════════════════════════════
# Step 2: SMB Share
# ═══════════════════════════════════════════════════════════════

function Install-SMBShare {
    Write-Banner "Step 2: SMB Share Setup"

    # Ensure vault path exists
    if (-not (Test-Path $Config.VaultPath)) {
        Write-Info "Vault path not found, creating directories first..."
        Install-Directories | Out-Null
    }

    # Create user
    $user = Get-LocalUser -Name $Config.SMBUser -ErrorAction SilentlyContinue
    if ($user) {
        Write-OK "User '$($Config.SMBUser)' exists"
    } else {
        Write-Info "Creating local user '$($Config.SMBUser)'..."
        $password = Read-Host "  Enter password for $($Config.SMBUser)" -AsSecureString
        try {
            New-LocalUser -Name $Config.SMBUser -Password $password -Description "SKI Vault SMB User" -PasswordNeverExpires | Out-Null
            Write-Created "User '$($Config.SMBUser)'"
        } catch {
            Write-Host "  [ERROR] Failed to create user: $_" -ForegroundColor Red
            return $false
        }
    }

    # Create share
    $share = Get-SmbShare -Name $Config.ShareName -ErrorAction SilentlyContinue
    if ($share) {
        Write-OK "Share '$($Config.ShareName)' exists at $($share.Path)"
    } else {
        try {
            New-SmbShare -Name $Config.ShareName -Path $Config.VaultPath `
                -FullAccess $Config.SMBUser -Description "SKI Obsidian Vault Root" | Out-Null
            Write-Created "Share '$($Config.ShareName)' -> $($Config.VaultPath)"
        } catch {
            Write-Host "  [ERROR] Failed to create share: $_" -ForegroundColor Red
            return $false
        }
    }

    # NTFS permissions
    try {
        $acl = Get-Acl $Config.VaultPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Config.SMBUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $Config.VaultPath $acl
        Write-OK "NTFS permissions set for '$($Config.SMBUser)'"
    } catch {
        Write-Host "  [ERROR] Failed to set permissions: $_" -ForegroundColor Red
        return $false
    }

    Write-Host "`n  [DONE] SMB share configured." -ForegroundColor Green
    return $true
}

# ═══════════════════════════════════════════════════════════════
# Step 3: Firewall Rules
# ═══════════════════════════════════════════════════════════════

function Install-FirewallRules {
    Write-Banner "Step 3: Firewall Rules"

    $rules = @(
        @{ Name = "SKI-LMStudio-API"; DisplayName = "SKI: LM Studio API (TCP $($Config.LMStudioPort))";
           Port = "$($Config.LMStudioPort)"; Desc = "Allow LM Studio API from VM" },
        @{ Name = "SKI-SMB-Vault"; DisplayName = "SKI: SMB Vault (TCP 445)";
           Port = "445"; Desc = "Allow SMB from VM" },
        @{ Name = "SKI-SSH-Inbound"; DisplayName = "SKI: SSH (TCP 22)";
           Port = "22"; Desc = "Allow SSH from VM" }
    )

    foreach ($rule in $rules) {
        $existing = Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Write-OK "$($rule.DisplayName)"
        } else {
            try {
                New-NetFirewallRule -Name $rule.Name -DisplayName $rule.DisplayName `
                    -Description $rule.Desc -Direction Inbound -Protocol TCP `
                    -LocalPort $rule.Port -RemoteAddress $Config.VMIP `
                    -Action Allow -Profile Any | Out-Null
                Write-Created "$($rule.DisplayName) (from $($Config.VMIP))"
            } catch {
                Write-Host "  [ERROR] Failed to create rule: $_" -ForegroundColor Red
                return $false
            }
        }
    }

    Write-Host "`n  [DONE] Firewall rules configured." -ForegroundColor Green
    return $true
}

# ═══════════════════════════════════════════════════════════════
# Step 4: Hyper-V VM
# ═══════════════════════════════════════════════════════════════

function Install-HyperVVM {
    Write-Banner "Step 4: Hyper-V VM"

    # Check Hyper-V
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERROR] Hyper-V is not available. Enable it first:" -ForegroundColor Red
        Write-Host "  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -ForegroundColor Yellow
        return $false
    }

    # Check existing VM
    $vm = Get-VM -Name $Config.VMName -ErrorAction SilentlyContinue
    if ($vm) {
        Write-OK "VM '$($Config.VMName)' exists (State: $($vm.State))"
        return $true
    }

    if (-not (Confirm-Proceed "Create VM '$($Config.VMName)' (16GB RAM, 4 vCPU, 120GB disk)?")) {
        Write-Info "Skipped VM creation."
        return $true
    }

    # Find switch
    $switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
    if (-not $switch) {
        $switch = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
    }
    if (-not $switch) {
        Write-Host "  [ERROR] No virtual switch found. Create one in Hyper-V Manager." -ForegroundColor Red
        return $false
    }
    $switchName = $switch.Name
    Write-Info "Using switch: $switchName"

    $vhdPath = "$($Config.VMPath)\$($Config.VMName).vhdx"

    try {
        New-VM -Name $Config.VMName -Generation 2 -MemoryStartupBytes $Config.RAM `
            -Path $Config.VMPath -NewVHDPath $vhdPath -NewVHDSizeBytes $Config.VHDSize `
            -SwitchName $switchName | Out-Null

        Set-VM -Name $Config.VMName -ProcessorCount $Config.CPUCount `
            -DynamicMemory -MemoryMinimumBytes 4GB -MemoryMaximumBytes $Config.RAM `
            -AutomaticStartAction Start -AutomaticStopAction ShutDown

        Set-VMFirmware -VMName $Config.VMName -EnableSecureBoot Off

        Write-Created "VM '$($Config.VMName)'"
    } catch {
        Write-Host "  [ERROR] VM creation failed: $_" -ForegroundColor Red
        return $false
    }

    Write-Host "`n  Manual next steps:" -ForegroundColor Yellow
    Write-Host "    1. Mount Ubuntu 24.04 ISO in Hyper-V Manager" -ForegroundColor Gray
    Write-Host "    2. Start VM and install Ubuntu" -ForegroundColor Gray
    Write-Host "    3. User: archat, hostname: 28bots-orchestrator" -ForegroundColor Gray
    Write-Host "    4. Static IP: $($Config.VMIP)" -ForegroundColor Gray
    Write-Host "    5. Install SSH: sudo apt install openssh-server" -ForegroundColor Gray
    return $true
}

# ═══════════════════════════════════════════════════════════════
# Step 5: Auto Research Setup
# ═══════════════════════════════════════════════════════════════

function Install-AutoResearch {
    Write-Banner "Step 5: Auto Research (Karpathy-style experiment loop)"

    $arDir = $Config.AutoResearchDir
    $srcDir = "$arDir\src"
    $logsDir = "$arDir\logs"
    $vaultResultsDir = "$($Config.VaultPath)\SKI_Cookbook\M12_AutoResearch"

    # Check Python
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $pyVer = python --version 2>&1
        Write-OK "Python: $pyVer"
    } else {
        Write-Host "  [ERROR] Python not found. Install Python 3.10+ from https://python.org" -ForegroundColor Red
        return $false
    }

    # Check GPU
    $nvSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvSmi) {
        $gpu = nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>&1
        Write-OK "GPU: $gpu"
    } else {
        Write-Host "  [WARN] nvidia-smi not found — GPU training may not work" -ForegroundColor Yellow
    }

    # Create directories
    foreach ($dir in @($arDir, $srcDir, $logsDir, "$arDir\backups", $vaultResultsDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Created $dir
        } else {
            Write-OK $dir
        }
    }

    # Create virtual environment
    $venvDir = "$arDir\.venv"
    if (Test-Path "$venvDir\Scripts\python.exe") {
        Write-OK "Virtual environment exists"
    } else {
        Write-Info "Creating virtual environment..."
        $uv = Get-Command uv -ErrorAction SilentlyContinue
        if ($uv) {
            uv venv $venvDir
        } else {
            python -m venv $venvDir
        }
        Write-Created "Virtual environment at $venvDir"
    }

    # Install dependencies
    Write-Info "Installing dependencies..."
    try {
        & "$venvDir\Scripts\pip.exe" install torch numpy tiktoken openai --quiet 2>&1 | Out-Null
        Write-OK "Dependencies installed"
    } catch {
        Write-Host "  [WARN] Some dependencies failed: $_" -ForegroundColor Yellow
    }

    # Copy source files from repo (if available)
    $repoPaths = @(
        "$PSScriptRoot\..\..\..\..\src\autoresearch",
        "$env:USERPROFILE\28BotsTST\src\autoresearch",
        "D:\28BotsTST\src\autoresearch"
    )
    $repoSrc = $null
    foreach ($p in $repoPaths) {
        if (Test-Path "$p\ski_runner.py") { $repoSrc = $p; break }
    }

    if ($repoSrc) {
        foreach ($f in @("ski_runner.py","train.py","prepare.py","config.py","program.md")) {
            if (Test-Path "$repoSrc\$f") {
                Copy-Item "$repoSrc\$f" "$srcDir\$f" -Force
                Write-OK "Copied $f"
            }
        }
    } else {
        Write-Info "Source files not found locally. Clone the repo and copy src/autoresearch/* to $srcDir"
    }

    # Create launcher scripts
    $launcherContent = @"
param([int]`$MaxExperiments = 100, [int]`$Budget = 300)
`$env:SKI_LM_STUDIO_BASE_URL = "http://localhost:$($Config.LMStudioPort)/v1"
`$env:SKI_AUTORESEARCH_MODEL = "$($Config.AutoResearchModel)"
`$env:SKI_AUTORESEARCH_BUDGET = "`$Budget"
`$env:SKI_AUTORESEARCH_MAX_EXPERIMENTS = "`$MaxExperiments"
`$env:SKI_VAULT_PATH = "$($Config.VaultPath)"
& "$venvDir\Scripts\python.exe" "$srcDir\ski_runner.py" --max-experiments `$MaxExperiments --budget `$Budget
"@
    Set-Content -Path "$arDir\run_autoresearch.ps1" -Value $launcherContent
    Write-Created "run_autoresearch.ps1"

    $overnightContent = @"
`$ts = Get-Date -Format "yyyyMMdd_HHmmss"
`$log = "$logsDir\overnight_`$ts.log"
Write-Host "Overnight run — log: `$log" -ForegroundColor Cyan
& "$arDir\run_autoresearch.ps1" -MaxExperiments 200 -Budget 300 2>&1 | Tee-Object -FilePath `$log
"@
    Set-Content -Path "$arDir\run_overnight.ps1" -Value $overnightContent
    Write-Created "run_overnight.ps1"

    Write-Host "`n  [DONE] Auto Research configured at $arDir" -ForegroundColor Green
    Write-Host "  Quick start: cd $arDir && .\run_autoresearch.ps1 -MaxExperiments 10" -ForegroundColor Gray
    return $true
}

# ═══════════════════════════════════════════════════════════════
# Remote VM Setup (SSH)
# ═══════════════════════════════════════════════════════════════

function Invoke-RemoteVMSetup {
    Write-Banner "Remote VM Setup via SSH"

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERROR] SSH client not found." -ForegroundColor Red
        Write-Host "  Enable: Settings > Apps > Optional Features > OpenSSH Client" -ForegroundColor Yellow
        return $false
    }

    $target = "$($Config.VMUser)@$($Config.VMIP)"
    Write-Info "Testing SSH to $target..."

    $testResult = ssh -o ConnectTimeout=5 -o BatchMode=yes $target "echo SSH_OK" 2>&1
    if ($testResult -notmatch "SSH_OK") {
        Write-Host "  [ERROR] SSH connection failed to $target" -ForegroundColor Red
        Write-Host "  Ensure VM is running, SSH is installed, and keys are configured." -ForegroundColor Yellow
        return $false
    }
    Write-OK "SSH connection successful"

    # Check scripts exist
    $scriptCount = ssh $target "ls $($Config.BootstrapPath)/*.sh 2>/dev/null | wc -l"
    if ([int]$scriptCount -lt 1) {
        Write-Host "  [ERROR] No scripts at $($Config.BootstrapPath)" -ForegroundColor Red
        Write-Host "  Ensure vault SMB mount is active on the VM." -ForegroundColor Yellow
        return $false
    }
    Write-OK "Found $scriptCount scripts on VM"

    ssh $target "chmod +x $($Config.BootstrapPath)/*.sh"

    $scripts = @(
        @{ File = "01_setup_base.sh";      Desc = "Base packages & system config" },
        @{ File = "02_setup_smb_mount.sh";  Desc = "SMB mount configuration" },
        @{ File = "03_setup_docker.sh";     Desc = "Docker installation" }
    )

    foreach ($s in $scripts) {
        Write-Host "`n  --- $($s.File): $($s.Desc) ---" -ForegroundColor Cyan
        ssh $target "sudo bash $($Config.BootstrapPath)/$($s.File)"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ERROR] $($s.File) failed (exit $LASTEXITCODE)" -ForegroundColor Red
            return $false
        }
        Write-OK "$($s.File) completed"
    }

    Write-Host "`n  [DONE] VM base setup complete." -ForegroundColor Green
    Write-Host "`n  Remaining manual steps:" -ForegroundColor Yellow
    Write-Host "    1. SSH: ssh $target" -ForegroundColor Gray
    Write-Host "    2. Log out and back in (Docker group)" -ForegroundColor Gray
    Write-Host "    3. Run: bash $($Config.BootstrapPath)/04_deploy_containers.sh" -ForegroundColor Gray
    Write-Host "    4. Run: bash $($Config.BootstrapPath)/05_setup_hermes.sh" -ForegroundColor Gray
    Write-Host "    5. Run: bash $($Config.BootstrapPath)/06_verify_vm.sh" -ForegroundColor Gray
    return $true
}

# ═══════════════════════════════════════════════════════════════
# Sanity Check
# ═══════════════════════════════════════════════════════════════

function Invoke-SanityCheck {
    Write-Host "`n" -NoNewline
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "       SKI SANITY CHECK" -ForegroundColor Cyan
    Write-Host "       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "  ============================================" -ForegroundColor Cyan

    Reset-Counters

    # ── 1. Directories ──
    Write-Banner "1. Directories"
    $dirs = @(
        "D:\28Bots_Core",
        "D:\28Bots_Core\Obsidian_Vault",
        $Config.VaultPath,
        "$($Config.VaultPath)\SKI_Cookbook",
        "$($Config.VaultPath)\SKI_Bootstrap",
        "$($Config.VaultPath)\SKI_Pilot",
        "D:\28Bots\Models\LLM_LIB",
        $Config.VMPath
    )
    foreach ($dir in $dirs) {
        if (Test-Path $dir) { Write-Pass $dir } else { Write-Fail "$dir not found" }
    }
    # Check M00-M11
    $cookbookCount = 0
    for ($i = 0; $i -le 11; $i++) {
        $m = "$($Config.VaultPath)\SKI_Cookbook\M{0:D2}" -f $i
        if (Test-Path $m) { $cookbookCount++ }
    }
    if ($cookbookCount -eq 12) { Write-Pass "Cookbook M00-M11 complete ($cookbookCount/12)" }
    elseif ($cookbookCount -gt 0) { Write-Warn "Cookbook modules: $cookbookCount/12" }
    else { Write-Fail "Cookbook M00-M11 missing" }

    # ── 2. SMB Share ──
    Write-Banner "2. SMB Share"
    $share = Get-SmbShare -Name $Config.ShareName -ErrorAction SilentlyContinue
    if ($share) {
        Write-Pass "Share '$($Config.ShareName)' at $($share.Path)"
        if ($share.Path -eq $Config.VaultPath) { Write-Pass "Share path matches config" }
        else { Write-Warn "Share path '$($share.Path)' differs from config '$($Config.VaultPath)'" }
    } else { Write-Fail "Share '$($Config.ShareName)' not found" }

    $user = Get-LocalUser -Name $Config.SMBUser -ErrorAction SilentlyContinue
    if ($user) {
        Write-Pass "User '$($Config.SMBUser)' exists"
        if ($user.Enabled) { Write-Pass "User '$($Config.SMBUser)' is enabled" }
        else { Write-Warn "User '$($Config.SMBUser)' is disabled" }
    } else { Write-Fail "User '$($Config.SMBUser)' not found" }

    # ── 3. Firewall ──
    Write-Banner "3. Firewall Rules"
    foreach ($ruleName in @("SKI-LMStudio-API", "SKI-SMB-Vault", "SKI-SSH-Inbound")) {
        $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if ($rule -and $rule.Enabled -eq "True") {
            Write-Pass "Rule '$ruleName' active"
        } elseif ($rule) {
            Write-Warn "Rule '$ruleName' exists but disabled"
        } else {
            Write-Fail "Rule '$ruleName' not found"
        }
    }

    # ── 4. Hyper-V VM ──
    Write-Banner "4. Hyper-V VM"
    if (Get-Command Get-VM -ErrorAction SilentlyContinue) {
        $vm = Get-VM -Name $Config.VMName -ErrorAction SilentlyContinue
        if ($vm) {
            Write-Pass "VM '$($Config.VMName)' exists"
            if ($vm.State -eq "Running") { Write-Pass "VM is running" }
            else { Write-Warn "VM state: $($vm.State)" }

            $ramGB = [math]::Round($vm.MemoryAssigned / 1GB, 1)
            if ($ramGB -ge 16) { Write-Pass "VM RAM: ${ramGB} GB" }
            elseif ($ramGB -ge 9) { Write-Warn "VM RAM: ${ramGB} GB (16 GB recommended)" }
            else { Write-Fail "VM RAM: ${ramGB} GB (minimum 9 GB)" }

            if ($vm.ProcessorCount -ge 4) { Write-Pass "VM CPUs: $($vm.ProcessorCount)" }
            else { Write-Warn "VM CPUs: $($vm.ProcessorCount) (4 recommended)" }
        } else { Write-Fail "VM '$($Config.VMName)' not found" }
    } else { Write-Fail "Hyper-V not available" }

    # ── 5. LM Studio ──
    Write-Banner "5. LM Studio"
    $lmUrl = "http://localhost:$($Config.LMStudioPort)"
    try {
        $models = Invoke-RestMethod -Uri "$lmUrl/v1/models" -TimeoutSec 5 -ErrorAction Stop
        Write-Pass "LM Studio API responding on :$($Config.LMStudioPort)"
        $modelCount = $models.data.Count
        Write-Pass "Models loaded: $modelCount"
        foreach ($m in $models.data) {
            Write-Info "  Model: $($m.id)"
        }

        # Inference test
        if ($modelCount -gt 0) {
            Write-Info "Running inference test..."
            $body = @{
                model      = $models.data[0].id
                messages   = @(@{ role = "user"; content = "Reply with only: OK" })
                max_tokens = 5
                temperature = 0
            } | ConvertTo-Json -Depth 5

            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $inference = Invoke-RestMethod -Uri "$lmUrl/v1/chat/completions" `
                    -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
                $sw.Stop()
                $reply = $inference.choices[0].message.content
                if ($reply) {
                    Write-Pass "Inference OK ($($sw.ElapsedMilliseconds)ms) — Response: $reply"
                } else {
                    Write-Warn "Inference returned empty response"
                }
            } catch {
                Write-Fail "Inference test failed: $_"
            }

            # Embedding test
            $embedModel = $models.data | Where-Object { $_.id -match "embed|nomic" } | Select-Object -First 1
            if ($embedModel) {
                Write-Info "Running embedding test with $($embedModel.id)..."
                $embedBody = @{
                    model = $embedModel.id
                    input = "SKI sanity check"
                } | ConvertTo-Json -Depth 5
                try {
                    $embedResult = Invoke-RestMethod -Uri "$lmUrl/v1/embeddings" `
                        -Method Post -Body $embedBody -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop
                    if ($embedResult.data[0].embedding) {
                        $dims = $embedResult.data[0].embedding.Count
                        Write-Pass "Embedding OK ($dims dimensions)"
                    } else {
                        Write-Warn "Embedding returned no data"
                    }
                } catch {
                    Write-Warn "Embedding test failed: $_"
                }
            }
        }
    } catch {
        Write-Fail "LM Studio API not responding on :$($Config.LMStudioPort)"
        Write-Info "Ensure LM Studio is running with the API server enabled."
    }

    # ── 6. Network ──
    Write-Banner "6. Network"
    if (Test-Connection -ComputerName $Config.VMIP -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        Write-Pass "VM reachable at $($Config.VMIP)"
    } else {
        Write-Fail "VM unreachable at $($Config.VMIP)"
    }

    # Port tests
    foreach ($entry in @(@{Port=22; Name="SSH"}, @{Port=445; Name="SMB"})) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $result = $tcp.BeginConnect($Config.VMIP, $entry.Port, $null, $null)
            $wait = $result.AsyncWaitHandle.WaitOne(3000, $false)
            if ($wait -and $tcp.Connected) {
                Write-Pass "VM port $($entry.Port) ($($entry.Name)) open"
            } else {
                Write-Warn "VM port $($entry.Port) ($($entry.Name)) closed or filtered"
            }
            $tcp.Close()
        } catch {
            Write-Warn "VM port $($entry.Port) ($($entry.Name)) test failed"
        }
    }

    # ── 7. SSH ──
    Write-Banner "7. SSH Connectivity"
    if (Get-Command ssh -ErrorAction SilentlyContinue) {
        Write-Pass "SSH client available"
        $target = "$($Config.VMUser)@$($Config.VMIP)"
        $sshTest = ssh -o ConnectTimeout=5 -o BatchMode=yes $target "echo SSH_OK" 2>&1
        if ($sshTest -match "SSH_OK") {
            Write-Pass "SSH login to $target successful"

            # ── 8. Vault mount on VM ──
            Write-Banner "8. Vault Mount (via SSH)"
            $mountCheck = ssh -o ConnectTimeout=5 $target "mountpoint -q /mnt/28bots_core && echo MOUNTED || echo NOT_MOUNTED" 2>&1
            if ($mountCheck -match "MOUNTED") {
                Write-Pass "Vault mounted on VM at /mnt/28bots_core"
            } else {
                Write-Fail "Vault NOT mounted on VM"
            }

            $fstabCheck = ssh -o ConnectTimeout=5 $target "grep -q 'x-systemd.automount' /etc/fstab && echo HAS_AUTOMOUNT || echo NO_AUTOMOUNT" 2>&1
            if ($fstabCheck -match "HAS_AUTOMOUNT") {
                Write-Pass "fstab has x-systemd.automount"
            } else {
                Write-Warn "fstab missing x-systemd.automount"
            }

            $fileCount = ssh -o ConnectTimeout=5 $target "find /mnt/28bots_core -maxdepth 2 -type f 2>/dev/null | wc -l" 2>&1
            Write-Info "Files on vault mount (depth 2): $($fileCount.Trim())"

            # Docker check
            $dockerCheck = ssh -o ConnectTimeout=5 $target "docker ps --format '{{.Names}}' 2>/dev/null | wc -l" 2>&1
            if ($dockerCheck.Trim() -match '^\d+$' -and [int]$dockerCheck.Trim() -gt 0) {
                Write-Pass "Docker running on VM ($($dockerCheck.Trim()) containers)"
            } else {
                Write-Warn "Docker not running or no containers on VM"
            }
        } else {
            Write-Warn "SSH login failed (key-based auth may not be set up)"
            Write-Info "SSH checks 7-8 skipped"
        }
    } else {
        Write-Warn "SSH client not found — skipping SSH checks"
    }

    # ── 9. Auto Research ──
    Write-Banner "9. Auto Research"
    $arDir = $Config.AutoResearchDir
    if (Test-Path $arDir) {
        Write-Pass "Auto Research directory: $arDir"

        if (Test-Path "$arDir\.venv\Scripts\python.exe") {
            Write-Pass "Python venv exists"
        } else {
            Write-Warn "Python venv not found at $arDir\.venv"
        }

        if (Test-Path "$arDir\src\ski_runner.py") {
            Write-Pass "Source files present"
        } else {
            Write-Warn "Source files missing at $arDir\src\"
        }

        if (Test-Path "$arDir\run_autoresearch.ps1") {
            Write-Pass "Launcher script exists"
        } else {
            Write-Warn "Launcher script missing"
        }

        # Check for experiment results
        $vaultResults = "$($Config.VaultPath)\SKI_Cookbook\M12_AutoResearch\results.jsonl"
        if (Test-Path $vaultResults) {
            $lines = (Get-Content $vaultResults | Measure-Object -Line).Lines
            $kept = (Select-String -Path $vaultResults -Pattern '"kept": true' -SimpleMatch | Measure-Object).Count
            Write-Pass "Experiments: $lines total ($kept kept)"

            # Show latest
            $latest = Get-Content $vaultResults | Select-Object -Last 1
            if ($latest) {
                try {
                    $exp = $latest | ConvertFrom-Json
                    Write-Info "Latest: val_bpb=$($exp.val_bpb) — $($exp.description)"
                } catch {}
            }
        } else {
            Write-Info "No experiments run yet"
        }

        # GPU check
        if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            $gpuMem = nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>&1
            Write-Pass "GPU: $gpuMem"
        } else {
            Write-Warn "nvidia-smi not available"
        }
    } else {
        Write-Warn "Auto Research not set up ($arDir not found)"
        Write-Info "Run Step 5 or 07_setup_autoresearch.ps1 to set up"
    }

    # ── Summary ──
    $result = Show-Summary "Sanity Check"
    return $result
}

# ═══════════════════════════════════════════════════════════════
# Menu System
# ═══════════════════════════════════════════════════════════════

function Show-StepMenu {
    do {
        Write-Host "`n" -NoNewline
        Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan
        Write-Host "  |           Individual Steps                    |" -ForegroundColor DarkCyan
        Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan
        Write-Host "  |  1. Create Directory Structure                |" -ForegroundColor White
        Write-Host "  |  2. Setup SMB Share + skiuser                 |" -ForegroundColor White
        Write-Host "  |  3. Configure Firewall Rules                  |" -ForegroundColor White
        Write-Host "  |  4. Create Hyper-V VM                         |" -ForegroundColor White
        Write-Host "  |  5. Setup Auto Research                       |" -ForegroundColor White
        Write-Host "  |  B. Back                                      |" -ForegroundColor Gray
        Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan

        $choice = Read-Host "`n  Select"
        switch ($choice) {
            "1" { Install-Directories | Out-Null }
            "2" { Install-SMBShare | Out-Null }
            "3" { Install-FirewallRules | Out-Null }
            "4" { Install-HyperVVM | Out-Null }
            "5" { Install-AutoResearch | Out-Null }
            "B" { return }
            "b" { return }
            default { Write-Host "  Invalid selection." -ForegroundColor Red }
        }
    } while ($true)
}

function Show-MainMenu {
    Write-Host "`n" -NoNewline
    Write-Host "  ================================================" -ForegroundColor Cyan
    Write-Host "    SKI Installer" -ForegroundColor Cyan
    Write-Host "    Sephirotische Kernintelligenz" -ForegroundColor Gray
    Write-Host "    Windows Server 2025" -ForegroundColor Gray
    Write-Host "  ================================================" -ForegroundColor Cyan

    do {
        Write-Host "`n" -NoNewline
        Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan
        Write-Host "  |              Main Menu                        |" -ForegroundColor DarkCyan
        Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan
        Write-Host "  |  1. Full Install (Steps 1-5)                  |" -ForegroundColor White
        Write-Host "  |  2. Sanity Check (Verify Everything)          |" -ForegroundColor White
        Write-Host "  |  3. Individual Steps  >>>                     |" -ForegroundColor White
        Write-Host "  |  4. Remote VM Setup (SSH)                     |" -ForegroundColor White
        Write-Host "  |  C. Show Config                               |" -ForegroundColor Gray
        Write-Host "  |  Q. Quit                                      |" -ForegroundColor Gray
        Write-Host "  +----------------------------------------------+" -ForegroundColor DarkCyan

        $choice = Read-Host "`n  Select"
        switch ($choice) {
            "1" {
                Write-Banner "FULL INSTALL"
                Show-Config
                if (Confirm-Proceed "Proceed with full installation?") {
                    $ok = Install-Directories
                    if ($ok) { $ok = Install-SMBShare }
                    if ($ok) { $ok = Install-FirewallRules }
                    if ($ok) { $ok = Install-HyperVVM }
                    if ($ok) { $ok = Install-AutoResearch }
                    if ($ok) {
                        Write-Host "`n  Full install complete." -ForegroundColor Green
                        if (Confirm-Proceed "Run sanity check now?") { Invoke-SanityCheck | Out-Null }
                    } else {
                        Write-Host "`n  Install stopped due to errors." -ForegroundColor Red
                    }
                }
            }
            "2" { Invoke-SanityCheck | Out-Null }
            "3" { Show-StepMenu }
            "4" { Invoke-RemoteVMSetup | Out-Null }
            "C" { Show-Config }
            "c" { Show-Config }
            "Q" { Write-Host "`n  Goodbye.`n" -ForegroundColor Gray; return }
            "q" { Write-Host "`n  Goodbye.`n" -ForegroundColor Gray; return }
            default { Write-Host "  Invalid selection." -ForegroundColor Red }
        }
    } while ($true)
}

# ═══════════════════════════════════════════════════════════════
# Entry Point
# ═══════════════════════════════════════════════════════════════

switch ($Mode) {
    "FullInstall"  {
        Install-Directories | Out-Null
        Install-SMBShare | Out-Null
        Install-FirewallRules | Out-Null
        Install-HyperVVM | Out-Null
        Install-AutoResearch | Out-Null
    }
    "SanityCheck"  { Invoke-SanityCheck | Out-Null }
    "Step1"        { Install-Directories | Out-Null }
    "Step2"        { Install-SMBShare | Out-Null }
    "Step3"        { Install-FirewallRules | Out-Null }
    "Step4"        { Install-HyperVVM | Out-Null }
    "Step5"        { Install-AutoResearch | Out-Null }
    "RemoteSetup"  { Invoke-RemoteVMSetup | Out-Null }
    "Menu"         { Show-MainMenu }
}
