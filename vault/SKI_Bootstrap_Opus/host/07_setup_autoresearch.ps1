#Requires -Version 5.1
<#
.SYNOPSIS
    SKI Bootstrap — Host Step 7: Setup Auto Research environment
.DESCRIPTION
    Configures the Auto Research workspace on the Windows host.
    Requires: Python 3.10+, uv, CUDA toolkit, LM Studio running.
    Does NOT install Python or CUDA — only configures the workspace.
.NOTES
    Based on Karpathy's autoresearch pattern, adapted for SKI.
    Run AFTER LM Studio is running with Bonsai Prism 8B loaded.
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== SKI Bootstrap: Auto Research Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── Configuration ──
$AutoResearchDir = "D:\28Bots_Core\AutoResearch"
$VaultResultsDir = "D:\28Bots_Core\Obsidian_Vault\root\SKI_Cookbook\M12_AutoResearch"
$RepoDir = "D:\28Bots_Core\AutoResearch\autoresearch"
$LMStudioURL = "http://localhost:1234/v1"

# ── 1. Check prerequisites ──
Write-Host "--- Checking Prerequisites ---" -ForegroundColor Cyan

# Python
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $pyVer = python --version 2>&1
    Write-Host "  [OK] $pyVer" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Python not found in PATH." -ForegroundColor Red
    Write-Host "  Install Python 3.10+ from https://python.org" -ForegroundColor Yellow
    exit 1
}

# uv (fast Python package manager)
$uv = Get-Command uv -ErrorAction SilentlyContinue
if ($uv) {
    $uvVer = uv --version 2>&1
    Write-Host "  [OK] uv: $uvVer" -ForegroundColor Green
} else {
    Write-Host "  [WARN] uv not found. Installing..." -ForegroundColor Yellow
    try {
        Invoke-Expression "& { $(Invoke-RestMethod https://astral.sh/uv/install.ps1) }"
        Write-Host "  [OK] uv installed" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Failed to install uv: $_" -ForegroundColor Red
        Write-Host "  Install manually: https://docs.astral.sh/uv/" -ForegroundColor Yellow
        exit 1
    }
}

# CUDA
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $gpuInfo = nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>&1
    Write-Host "  [OK] GPU: $gpuInfo" -ForegroundColor Green
} else {
    Write-Host "  [WARN] nvidia-smi not found. GPU training may not work." -ForegroundColor Yellow
}

# LM Studio
Write-Host "  Checking LM Studio API..." -NoNewline
try {
    $models = Invoke-RestMethod -Uri "$LMStudioURL/models" -TimeoutSec 5
    $count = $models.data.Count
    Write-Host " [OK] $count models loaded" -ForegroundColor Green
} catch {
    Write-Host " [WARN] LM Studio not responding on $LMStudioURL" -ForegroundColor Yellow
    Write-Host "  Start LM Studio and load Bonsai Prism 8B before running experiments." -ForegroundColor Yellow
}

# ── 2. Create directory structure ──
Write-Host ""
Write-Host "--- Creating Directories ---" -ForegroundColor Cyan

$dirs = @(
    $AutoResearchDir,
    "$AutoResearchDir\logs",
    "$AutoResearchDir\backups",
    $VaultResultsDir
)

foreach ($dir in $dirs) {
    if (Test-Path $dir) {
        Write-Host "  [OK] $dir" -ForegroundColor Green
    } else {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  [CREATED] $dir" -ForegroundColor Yellow
    }
}

# ── 3. Clone/copy Auto Research files ──
Write-Host ""
Write-Host "--- Setting Up Auto Research Files ---" -ForegroundColor Cyan

# Check if repo files exist (from 28BotsTST clone)
$repoSrc = "D:\28Bots_Core\Obsidian_Vault\root\SKI_Bootstrap_Opus"
$srcFiles = @("ski_runner.py", "train.py", "prepare.py", "config.py", "program.md")

# Try to find source files from the git repo
$gitRepoSrc = $null
$possiblePaths = @(
    "$env:USERPROFILE\28BotsTST\src\autoresearch",
    "D:\28BotsTST\src\autoresearch",
    "C:\28BotsTST\src\autoresearch"
)
foreach ($p in $possiblePaths) {
    if (Test-Path "$p\ski_runner.py") {
        $gitRepoSrc = $p
        break
    }
}

$targetDir = "$AutoResearchDir\src"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

if ($gitRepoSrc) {
    Write-Host "  [OK] Found source files at $gitRepoSrc" -ForegroundColor Green
    foreach ($file in $srcFiles) {
        $src = "$gitRepoSrc\$file"
        $dst = "$targetDir\$file"
        if (Test-Path $src) {
            Copy-Item $src $dst -Force
            Write-Host "  [COPIED] $file" -ForegroundColor Green
        }
    }
} else {
    Write-Host "  [INFO] Source files not found in common locations." -ForegroundColor Yellow
    Write-Host "  Clone the repo: git clone https://github.com/IdomyownGPT/28BotsTST.git" -ForegroundColor Yellow
    Write-Host "  Then copy src/autoresearch/* to $targetDir" -ForegroundColor Yellow
}

# ── 4. Create Python virtual environment ──
Write-Host ""
Write-Host "--- Python Environment ---" -ForegroundColor Cyan

$venvDir = "$AutoResearchDir\.venv"
if (Test-Path "$venvDir\Scripts\python.exe") {
    Write-Host "  [OK] Virtual environment exists at $venvDir" -ForegroundColor Green
} else {
    Write-Host "  Creating virtual environment..."
    try {
        uv venv $venvDir
        Write-Host "  [CREATED] $venvDir" -ForegroundColor Yellow
    } catch {
        Write-Host "  [WARN] uv venv failed, trying python -m venv..." -ForegroundColor Yellow
        python -m venv $venvDir
    }
}

# Install dependencies
Write-Host "  Installing dependencies..."
$requirements = @(
    "torch",
    "numpy",
    "tiktoken",
    "openai"
)

try {
    & "$venvDir\Scripts\pip.exe" install $requirements --quiet 2>&1 | Out-Null
    Write-Host "  [OK] Dependencies installed (torch, numpy, tiktoken, openai)" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Some dependencies may have failed. Check manually." -ForegroundColor Yellow
}

# ── 5. Create launcher script ──
Write-Host ""
Write-Host "--- Creating Launcher ---" -ForegroundColor Cyan

$launcherPath = "$AutoResearchDir\run_autoresearch.ps1"
$launcherContent = @'
# SKI Auto Research — Launcher
# Usage: .\run_autoresearch.ps1 [-MaxExperiments 50] [-Budget 300]

param(
    [int]$MaxExperiments = 100,
    [int]$Budget = 300
)

$ErrorActionPreference = "Stop"
$env:SKI_LM_STUDIO_BASE_URL = "http://localhost:1234/v1"
$env:SKI_AUTORESEARCH_MODEL = "bonsai-prism-8b"
$env:SKI_AUTORESEARCH_BUDGET = "$Budget"
$env:SKI_AUTORESEARCH_MAX_EXPERIMENTS = "$MaxExperiments"
$env:SKI_VAULT_PATH = "D:\28Bots_Core\Obsidian_Vault\root"

$venv = "D:\28Bots_Core\AutoResearch\.venv\Scripts\python.exe"
$runner = "D:\28Bots_Core\AutoResearch\src\ski_runner.py"

if (-not (Test-Path $venv)) {
    Write-Host "[ERROR] Virtual environment not found. Run 07_setup_autoresearch.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Starting SKI Auto Research..." -ForegroundColor Cyan
Write-Host "  Experiments: $MaxExperiments" -ForegroundColor Gray
Write-Host "  Budget: ${Budget}s per experiment" -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

& $venv $runner --max-experiments $MaxExperiments --budget $Budget
'@

Set-Content -Path $launcherPath -Value $launcherContent
Write-Host "  [CREATED] $launcherPath" -ForegroundColor Yellow

# ── 6. Create overnight runner ──
$overnightPath = "$AutoResearchDir\run_overnight.ps1"
$overnightContent = @'
# SKI Auto Research — Overnight Runner
# Runs experiments until stopped or max reached
# Usage: .\run_overnight.ps1

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "D:\28Bots_Core\AutoResearch\logs\overnight_$timestamp.log"

Write-Host "Starting overnight Auto Research session..." -ForegroundColor Cyan
Write-Host "Log: $logFile" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray

& "D:\28Bots_Core\AutoResearch\run_autoresearch.ps1" -MaxExperiments 200 -Budget 300 2>&1 |
    Tee-Object -FilePath $logFile

Write-Host "`nOvernight session complete. Log: $logFile" -ForegroundColor Green
'@

Set-Content -Path $overnightPath -Value $overnightContent
Write-Host "  [CREATED] $overnightPath" -ForegroundColor Yellow

# ── Summary ──
Write-Host ""
Write-Host "=== Auto Research Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "  Directory:  $AutoResearchDir" -ForegroundColor Gray
Write-Host "  Source:     $AutoResearchDir\src\" -ForegroundColor Gray
Write-Host "  Logs:       $AutoResearchDir\logs\" -ForegroundColor Gray
Write-Host "  Vault:      $VaultResultsDir" -ForegroundColor Gray
Write-Host ""
Write-Host "  Quick start:" -ForegroundColor Cyan
Write-Host "    cd $AutoResearchDir" -ForegroundColor White
Write-Host "    .\run_autoresearch.ps1                  # Default: 100 experiments" -ForegroundColor White
Write-Host "    .\run_autoresearch.ps1 -MaxExperiments 10  # Quick test" -ForegroundColor White
Write-Host "    .\run_overnight.ps1                     # Overnight: 200 experiments" -ForegroundColor White
Write-Host ""
Write-Host "  Steer research by editing:" -ForegroundColor Cyan
Write-Host "    $targetDir\program.md" -ForegroundColor White
Write-Host "  (Also visible in Obsidian at SKI_Cookbook/M12_AutoResearch)" -ForegroundColor Gray
Write-Host ""
