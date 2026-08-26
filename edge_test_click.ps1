# test_edge_click.ps1
# 引入 Windows API 与 .NET 核心程序集
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# 引入 Win32 API 模拟鼠标平滑滑行与点击
$APIs = @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;

    public static void SmoothMove(int startX, int startY, int endX, int endY, int steps = 25) {
        Random rand = new Random();
        int ctrlX1 = startX + (endX - startX) / 3 + rand.Next(-30, 30);
        int ctrlY1 = startY + (endY - startY) / 3 + rand.Next(-30, 30);
        int ctrlX2 = startX + (endX - startX) * 2 / 3 + rand.Next(-30, 30);
        int ctrlY2 = startY + (endY - startY) * 2 / 3 + rand.Next(-30, 30);

        for (int i = 0; i <= steps; i++) {
            float t = (float)i / steps;
            float u = 1 - t;

            int x = (int)(u*u*u*startX + 3*u*u*t*ctrlX1 + 3*u*t*t*ctrlX2 + t*t*t*endX);
            int y = (int)(u*u*u*startY + 3*u*u*t*ctrlY1 + 3*u*t*t*ctrlY2 + t*t*t*endX);

            SetCursorPos(x, y);
            Thread.Sleep(rand.Next(10, 20));
        }
        SetCursorPos(endX, endY);
    }

    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        Thread.Sleep(150);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(60);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }
}
"@
Add-Type -TypeDefinition $APIs

# 路径设置
$PSScriptDir = $PSScriptRoot
$ScrotDir = Join-Path $PSScriptDir "scrot_png"
$LogFile = Join-Path $PSScriptDir "edge_click.log"
$AccountFile = Join-Path $PSScriptDir "account.txt"

if (-not (Test-Path $ScrotDir)) { New-Item -ItemType Directory -Path $ScrotDir | Out-Null }

# 日志辅助函数
function Write-Log {
    param([string]$Message)
    $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $logLine = "[$time] - [INFO] - $Message"
    Write-Host $logLine
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
}

# 抓取当前全屏 Bitmap
function Get-ScreenBitmap {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $graphics.Dispose()
    return $bmp
}

# WinRT Windows.Media.Ocr 内存识别函数
function Find-TextOnScreen {
    param([string]$TargetText, [int]$MaxRetries = 15)
    Write-Log "Searching for screen keyword: [$TargetText] (Max retries: $MaxRetries)..."
    
    # 异步加载 Windows.Media.Ocr.OcrEngine
    [Windows.Media.Ocr.OcrEngine, Windows.Foundation.SegmentedMatrix, ContentType=WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation.SegmentedMatrix, ContentType=WindowsRuntime] | Out-Null
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguage()

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $bmp = Get-ScreenBitmap
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            
            $decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync([Windows.Storage.Streams.RandomAccessStream]::CreateForStream($ms.AsRandomAccessStream())).GetResults()
            $softBmp = $decoder.GetSoftwareBitmapAsync().GetResults()
            $ocrResult = $engine.RecognizeAsync($softBmp).GetResults()
            $ms.Dispose()

            if ($ocrResult.Text -like "*$TargetText*") {
                Write-Log "Matched keyword successfully on attempt $i: [$TargetText]"
                return $true
            }
        } catch {
            # 若 OcrEngine 渲染延迟则降级重试
        }
        Write-Log "Attempt $i/$MaxRetries did not match [$TargetText], retrying..."
        Start-Sleep -Seconds 2
    }
    Write-Log "Timeout waiting for text on screen: [$TargetText]"
    return $false
}

# 读取 account.txt 指定行
function Read-AccountLine {
    param([int]$LineNo)
    if (-not (Test-Path $AccountFile)) {
        throw "Account file not found: $AccountFile"
    }
    $lines = Get-Content $AccountFile | Where-Object { $_.Trim() -ne "" }
    return $lines[$LineNo - 1]
}

# 启动后台独立截图 Job
Write-Log "================ Start Native Edge GUI Automation ================"
Write-Log "Starting background screenshot job..."
$Global:ScrotScript = {
    param($ScrotDir)
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $count = 1
    while ($true) {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $filename = Join-Path $ScrotDir ("shot_{0}_{1:D4}.png" -f $timestamp, $count)
        $bmp.Save($filename, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose()
        $bmp.Dispose()
        $count++
        Start-Sleep -Seconds 1
    }
}
$ScrotJob = Start-Job -ScriptBlock $Global:ScrotScript -ArgumentList $ScrotDir

try {
    # 1. 启动原生 Edge 浏览器
    Write-Log "Launching Microsoft Edge (Maximized)..."
    Start-Process "msedge.exe" -ArgumentList "--start-maximized", "--no-first-run", "--no-default-browser-check", "https://signup.live.com/"
    Start-Sleep -Seconds 10

    # 2. 阶段 1: 匹配并输入 Email
    Find-TextOnScreen -TargetText "Create your Microsoft account" -MaxRetries 15
    Write-Log "Moving mouse to Email input field (371, 390) and clicking..."
    [WinAPI]::SmoothMove(100, 100, 371, 390, 20)
    [WinAPI]::ClickAt(371, 390)

    $email = Read-AccountLine -LineNo 1
    Write-Log "Typing Email text: $email"
    foreach ($char in $email.ToCharArray()) {
        [System.Windows.Forms.SendKeys]::SendWait($char)
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 100)
    }
    Start-Sleep -Seconds 2

    Write-Log "Clicking Next button (362, 464)..."
    [WinAPI]::SmoothMove(371, 390, 362, 464, 15)
    [WinAPI]::ClickAt(362, 464)

    # 3. 阶段 2: 匹配并输入 Password
    Find-TextOnScreen -TargetText "Create your password" -MaxRetries 15
    Write-Log "Moving mouse to Password input field (372, 435) and clicking..."
    [WinAPI]::SmoothMove(362, 464, 372, 435, 15)
    [WinAPI]::ClickAt(372, 435)

    $password = Read-AccountLine -LineNo 2
    Write-Log "Typing Password text: $password"
    foreach ($char in $password.ToCharArray()) {
        [System.Windows.Forms.SendKeys]::SendWait($char)
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 100)
    }
    Start-Sleep -Seconds 2

    Write-Log "Clicking Next button (359, 539)..."
    [WinAPI]::SmoothMove(372, 435, 359, 539, 15)
    [WinAPI]::ClickAt(359, 539)

    # 4. 阶段 3: 填写基本生日信息
    Find-TextOnScreen -TargetText "Add some details" -MaxRetries 15
    Write-Log "Selecting Month dropdown (351, 464)..."
    [WinAPI]::ClickAt(351, 464)
    [System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 1

    Write-Log "Selecting Day dropdown (471, 464)..."
    [WinAPI]::ClickAt(471, 464)
    [System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 1

    Write-Log "Moving mouse to Year input field (602, 464)..."
    [WinAPI]::ClickAt(602, 464)
    $year = Read-AccountLine -LineNo 3
    Write-Log "Typing Year text: $year"
    foreach ($char in $year.ToCharArray()) {
        [System.Windows.Forms.SendKeys]::SendWait($char)
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 100)
    }
    Start-Sleep -Seconds 2

    Write-Log "Clicking final Next button (351, 639)..."
    [WinAPI]::ClickAt(351, 639)
    Write-Log "All steps executed successfully. Holding screen for 15s..."
    Start-Sleep -Seconds 15

} catch {
    Write-Log "Fatal Error encountered during execution: $_"
} finally {
    Stop-Job -Job $ScrotJob | Out-Null
    Remove-Job -Job $ScrotJob | Out-Null
    Write-Log "Background screenshot job stopped."
    Write-Log "================ Automation Task Finished ================"
}
