# test_edge_run.ps1
$ErrorActionPreference = "Continue"

$PSScriptDir = $PSScriptRoot
$ScrotDir = Join-Path $PSScriptDir "scrot_png"
$ZipFile = Join-Path $PSScriptDir "scrot_png.zip"
$AccountFile = Join-Path $PSScriptDir "account.txt"
$ClickLogFile = Join-Path $PSScriptDir "edge_click.log"

function Run-StepLog([string]$Title) {
    Write-Host "`n================ $Title ================"
}

# 1. 准备工作目录
Run-StepLog "[1/5] Preparing Directories"
if (-not (Test-Path $ScrotDir)) { New-Item -ItemType Directory -Path $ScrotDir | Out-Null }

# 2. 动态获取 IP 时区并设置系统时区
Run-StepLog "[2/5] Setting Dynamic Windows TimeZone"
try {
    $ipInfo = Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 10
    $ianaTz = $ipInfo.timezone
    Write-Host "Detected IP Timezone: $ianaTz"
    $tzMap = @{
        "America/New_York" = "Eastern Standard Time"
        "America/Chicago"  = "Central Standard Time"
        "America/Los_Angeles" = "Pacific Standard Time"
        "Asia/Shanghai"    = "China Standard Time"
    }
    $winTz = $tzMap[$ianaTz]
    if (-not $winTz) { $winTz = "Eastern Standard Time" }
    tzutil /s "$winTz"
    Write-Host "Successfully set system timezone to: $winTz"
} catch {
    Write-Host "Failed to fetch dynamic timezone, using default Eastern Standard Time."
    tzutil /s "Eastern Standard Time"
}

# 3. 执行 account.sh 脚本生成账号
Run-StepLog "[3/5] Generating Account File via account.sh"
$gitBash = "C:\Program Files\Git\bin\bash.exe"
if (Test-Path $gitBash) {
    & "$gitBash" ./account.sh
} else {
    bash ./account.sh
}

if (-not (Test-Path $AccountFile)) {
    Write-Error "account.txt not found! Stopping execution."
    exit 1
}
$accLines = Get-Content $AccountFile | Where-Object { $_.Trim() -ne "" }
if ($accLines.Count -lt 3) {
    Write-Error "account.txt has insufficient lines (Requires at least 3 lines)."
    exit 1
}
Write-Host "Account file validation passed! Current registration Email: $($accLines[0])"

# 4. 运行主点击自动化逻辑
Run-StepLog "[4/5] Executing Native Edge Automation Script"
& "$PSScriptDir\test_edge_click.ps1"

# 5. 打包截图并提交产物
Run-StepLog "[5/5] Packaging Artifacts and Pushing to Git Repository"
if (Test-Path $ScrotDir) {
    if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
    Compress-Archive -Path "$ScrotDir\*" -DestinationPath $ZipFile -Force
    Write-Host "Screenshots packaged into: $ZipFile"
}

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

if (Test-Path $AccountFile) { git add -f "$AccountFile" }
if (Test-Path $ClickLogFile) { git add -f "$ClickLogFile" }
if (Test-Path $ZipFile) { git add -f "$ZipFile" }

git commit -m "chore(ci): save account.txt, edge_click log and scrot_png.zip [skip ci]"
if ($LASTEXITCODE -eq 0) {
    Write-Host "Pushing artifacts to remote repository..."
    git push origin main
} else {
    Write-Host "No changes to commit or status up-to-date."
}
