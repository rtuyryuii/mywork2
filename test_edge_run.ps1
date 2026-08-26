# test_edge_run.ps1
$ErrorActionPreference = "Stop"

$PSScriptDir = $PSScriptRoot
$ScrotDir = Join-Path $PSScriptDir "scrot_png"
$ZipFile = Join-Path $PSScriptDir "scrot_png.zip"
$AccountFile = Join-Path $PSScriptDir "account.txt"
$ClickLogFile = Join-Path $PSScriptDir "test_edge_click.log"

function Write-StepHeader([string]$Title) {
    Write-Host "`n================ $Title ================" -ForegroundColor Cyan
}

# 改造为：原生调用，实时将子脚本输出流直接抛给终端，解决死锁问题
function Invoke-SubPowerShellScript([string]$ScriptPath) {
    if (-not (Test-Path $ScriptPath)) {
        Write-Error "[ERROR] Sub-script not found: $ScriptPath"
        exit 1
    }

    Write-Host "[INFO] Executing: $ScriptPath" -ForegroundColor Yellow
    
    # 直接在同一个进程上下文运行，或者使用 powershell 命令行直接透传
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ScriptPath"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Script execution failed: $ScriptPath (Exit Code: $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

# =========================================================================
# 0. Check & Install Windows Native OCR Language Pack (与 test_ocr.yml 逻辑完全一致)
# =========================================================================
Write-StepHeader "[0/5] Checking Windows Native OCR Language Pack"
try {
    $capability = Get-WindowsCapability -Online | Where-Object Name -like "Language.Basic~~~en-US*"
    if ($capability.State -ne "Installed") {
        Write-Host "[INFO] OCR Language Pack (en-US) not found. Installing now..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name "Language.Basic~~~en-US~0.0.1.0"
        Write-Host "[SUCCESS] Windows Native OCR Language Pack installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Windows Native OCR Language Pack (en-US) is already installed." -ForegroundColor Green
    }
} catch {
    Write-Host "[WARN] Language pack check skipped: $_" -ForegroundColor Yellow
}

# =========================================================================
# 1. Update & Sync Dynamic Windows TimeZone
# =========================================================================
Write-StepHeader "[1/5] Updating Dynamic Windows TimeZone"
try {
    $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 10
    $ianaTz = $ipInfo.timezone
    Write-Host "[INFO] Detected IP Timezone: $ianaTz"
    $tzMap = @{
        "America/New_York"    = "Eastern Standard Time"
        "America/Chicago"     = "Central Standard Time"
        "America/Los_Angeles" = "Pacific Standard Time"
        "Asia/Shanghai"       = "China Standard Time"
    }
    $winTz = $tzMap[$ianaTz]
    if (-not $winTz) { $winTz = "Eastern Standard Time" }
    tzutil /s "$winTz"
    Write-Host "[INFO] Successfully set system timezone to: $winTz"
} catch {
    Write-Host "[WARN] Failed to fetch dynamic timezone, falling back to Eastern Standard Time." -ForegroundColor Yellow
    tzutil /s "Eastern Standard Time"
}

# =========================================================================
# 2. Run account.ps1 and Check account.txt
# =========================================================================
Write-StepHeader "[2/4] Executing account.ps1 & Validating account.txt"
$AccountScript = Join-Path $PSScriptDir "account.ps1"
if (Test-Path $AccountScript) {
    Invoke-SubPowerShellScript -ScriptPath $AccountScript
} else {
    Write-Host "[INFO] account.ps1 not found, assuming account.txt is pre-generated." -ForegroundColor Yellow
}

if (-not (Test-Path $AccountFile)) {
    Write-Error "[ERROR] Validation failed: $AccountFile does NOT exist!"
    exit 1
}

$accLines = Get-Content $AccountFile | Where-Object { $_.Trim() -ne "" }
if ($accLines.Count -lt 3) {
    Write-Error "[ERROR] Validation failed: $AccountFile has less than 3 lines!"
    exit 1
}
Write-Host "[SUCCESS] account.txt verified! Current Target Email: $($accLines[0])" -ForegroundColor Green

# =========================================================================
# 3. Run test_edge_click.ps1 and Check Logs & Screenshots Directory
# =========================================================================
Write-StepHeader "[3/4] Executing test_edge_click.ps1 & Validating Outputs"
$ClickScript = Join-Path $PSScriptDir "test_edge_click.ps1"
Invoke-SubPowerShellScript -ScriptPath $ClickScript

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

if (-not (Test-Path $ClickLogFile)) {
    Write-Error "[ERROR] Validation failed: $ClickLogFile does NOT exist!"
    exit 1
}

if (-not (Test-Path $ScrotDir)) {
    Write-Error "[ERROR] Validation failed: Directory $ScrotDir does NOT exist!"
    exit 1
}

$pngFiles = Get-ChildItem -Path $ScrotDir -Filter "*.png"
if ($pngFiles.Count -eq 0) {
    Write-Error "[ERROR] Validation failed: No PNG screenshots found in $ScrotDir!"
    exit 1
}
Write-Host "[SUCCESS] Found $($pngFiles.Count) screenshot(s) and log file successfully!" -ForegroundColor Green

# =========================================================================
# 4. Zip scrot_png Directory and Push Artifacts to Git
# =========================================================================
Write-StepHeader "[4/4] Packaging Screenshots and Pushing to Git Repository"
if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

Compress-Archive -Path "$ScrotDir\*" -DestinationPath $ZipFile -Force
if (-not (Test-Path $ZipFile)) {
    Write-Error "[ERROR] Packaging failed: Zip file $ZipFile was not created!"
    exit 1
}
Write-Host "[INFO] Screenshots packaged successfully -> $ZipFile"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

git add -f "$AccountFile" "$ClickLogFile" "$ZipFile"

$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Host "[INFO] Changes detected. Committing and pushing to remote..."
    git commit -m "chore(ci): update account.txt, test_edge_click.log and scrot_png.zip [skip ci]"
    
    git pull origin main --rebase
    git push origin HEAD:main

    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] git push failed with Exit Code: $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Host "[SUCCESS] All artifacts successfully updated and pushed to origin/main!" -ForegroundColor Green
} else {
    Write-Host "[WARN] No file changes detected to commit." -ForegroundColor Yellow
}
