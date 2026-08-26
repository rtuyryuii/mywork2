# test_edge_click.ps1 - Native Edge GUI Automation (Maximized Window)

$LogFile = "test_edge_click.log"
function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "$timestamp - INFO - $message"
    Write-Output $logMsg
    Add-Content -Path $LogFile -Value $logMsg
}

"" | Out-File -FilePath $LogFile -Encoding utf8
Write-Log "================ Start Native Edge GUI Automation ================"

# ---------------------------------------------------------
# Win32 API & System Assemblies
# ---------------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP   = 0x0004;
}
"@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------
function Get-RandomDelay {
    return Get-Random -Minimum 2 -Maximum 5
}

function Invoke-LeftClick {
    param([int]$X, [int]$Y)
    Write-Log "Clicking coordinate ($X, $Y)..."
    [Win32]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 150
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [System.UIntPtr]::Zero)
    [Win32]::mouse_event([Win32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [System.UIntPtr]::Zero)
    
    $delay = Get-RandomDelay
    Write-Log "Random pause for ${delay}s after click..."
    Start-Sleep -Seconds $delay
}

# 剪贴板粘贴方案：保证邮箱中的 @ 符号和任何特殊密码准确无误填入
function Send-AccountLineViaClipboard {
    param([int]$LineNumber, [string]$AccountFilePath = "account.txt")
    if (Test-Path $AccountFilePath) {
        $lines = Get-Content $AccountFilePath
        if ($lines.Count -ge $LineNumber) {
            $targetText = $lines[$LineNumber - 1].Trim()
            Write-Log "Pasting Line $LineNumber from account.txt -> [$targetText]"
            
            [System.Windows.Forms.Clipboard]::SetText($targetText)
            Start-Sleep -Milliseconds 200
            [System.Windows.Forms.SendKeys]::SendWait("^v")
            
            $delay = Get-RandomDelay
            Write-Log "Random pause for ${delay}s after typing..."
            Start-Sleep -Seconds $delay
        } else {
            Write-Log "Error: account.txt has fewer than $LineNumber lines."
        }
    } else {
        Write-Log "Error: $AccountFilePath not found!"
    }
}

# ---------------------------------------------------------
# 逐行 OCR 识图（采用显式 WinRT 加载，完美适配 Windows-latest Actions）
# ---------------------------------------------------------
function Wait-ForText {
    param([string]$TargetText, [int]$MaxRetries = 15)
    
    $OcrDumpFile = "ocr_dump.txt"
    Write-Log "Searching for screen keyword via OCR Dump: [$TargetText]..."

    # 1. 加载 WinRT 和内存流扩展程序集
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        Add-Type -AssemblyName "System.IO.WindowsRuntimeStreamExtensions, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" -ErrorAction SilentlyContinue
        $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, Version=255.255.255.255, Culture=neutral, PublicKeyToken=null, ContentType=WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, Version=255.255.255.255, Culture=neutral, PublicKeyToken=null, ContentType=WindowsRuntime]
        $null = [Windows.Globalization.Language, Windows.Globalization, Version=255.255.255.255, Culture=neutral, PublicKeyToken=null, ContentType=WindowsRuntime]
    } catch {
        Write-Log "Warning: Assembly pre-loading exception: $_"
    }

    # 2. 反射获取 Await 方法处理 WinRT 异步任务
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' 
    })[0]

    function Await-WinRt($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        return $netTask.Result
    }

    # 3. 初始化 OCR 引擎
    $lang = [Windows.Globalization.Language]::new("en-US")
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    if (-not $engine) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    }

    if (-not $engine) {
        Write-Log "Error: Native OCR Engine failed to load."
        return $false
    }

    # 4. OCR 轮询匹配逻辑
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            # 截屏到 .NET MemoryStream
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose()
            $bmp.Dispose()

            # 关键修复：使用 AsRandomAccessStream 进行纯内存转换
            $ms.Position = 0
            $randomAccessStream = [System.WindowsRuntimeSystemExtensions]::AsRandomAccessStream($ms)

            # WinRT OCR 解析流程
            $decoderAsync = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($randomAccessStream)
            $decoder = Await-WinRt $decoderAsync ([Windows.Graphics.Imaging.BitmapDecoder])

            $bitmapAsync = $decoder.GetSoftwareBitmapAsync()
            $softwareBitmap = Await-WinRt $bitmapAsync ([Windows.Graphics.Imaging.SoftwareBitmap])

            $ocrAsync = $engine.RecognizeAsync($softwareBitmap)
            $ocrResult = Await-WinRt $ocrAsync ([Windows.Media.Ocr.OcrResult])
            
            $randomAccessStream.Dispose()
            $ms.Dispose()

            # 提取文本
            $extractedLines = @()
            foreach ($line in $ocrResult.Lines) {
                if (-not [string]::IsNullOrWhiteSpace($line.Text)) {
                    $extractedLines += $line.Text.Trim()
                }
            }
            $currentScreenContent = $extractedLines -join "`n"

            # 写入 Dump 记录日志
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $dumpHeader = "================ OCR DUMP [Attempt $i - $timestamp] ================"
            Add-Content -Path $OcrDumpFile -Value "$dumpHeader`n$currentScreenContent`n" -Encoding UTF8

            # 验证目标关键字
            if ($currentScreenContent -like "*$TargetText*") {
                Write-Log "Matched exact text [$TargetText] on attempt ${i}!"
                return $true
            }
        } catch {
            Write-Log "Warning: Exception during OCR capture: $_"
        }

        Write-Log "Attempt ${i}/$MaxRetries did not match [$TargetText] in dump, retrying..."
        Start-Sleep -Seconds 2
    }

    Write-Log "Timeout waiting for text: [$TargetText]"
    return $false
}

# ---------------------------------------------------------
# Background Screenshot Monitor Process
# ---------------------------------------------------------
Write-Log "Starting background screenshot job..."
$WorkspacePath = (Get-Location).Path
$TargetScrotDir = Join-Path $WorkspacePath "scrot_png"

if (-not (Test-Path $TargetScrotDir)) {
    New-Item -ItemType Directory -Path $TargetScrotDir -Force | Out-Null
}

$ScreenshotScript = [scriptblock]::Create(@"
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    `$saveDir = "$TargetScrotDir"
    `$count = 1
    while (`$true) {
        try {
            `$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            `$bmp = New-Object System.Drawing.Bitmap `$bounds.Width, `$bounds.Height
            `$graphics = [System.Drawing.Graphics]::FromImage(`$bmp)
            `$graphics.CopyFromScreen(`$bounds.Location, [System.Drawing.Point]::Empty, `$bounds.Size)
            
            `$filename = "shot_{0}_{1:D4}.png" -f (Get-Date -Format "yyyyMMdd_HHmmss"), `$count
            `$fullPath = Join-Path `$saveDir `$filename
            `$bmp.Save(`$fullPath, [System.Drawing.Imaging.ImageFormat]::Png)
            `$graphics.Dispose()
            `$bmp.Dispose()
            `$count++
        } catch {}
        Start-Sleep -Seconds 1
    }
"@)

$job = Start-Job -ScriptBlock $ScreenshotScript

# ---------------------------------------------------------
# Main Execution Workflow
# ---------------------------------------------------------
try {
    Write-Log "Launching Microsoft Edge (Maximized)..."
    Start-Process "msedge.exe" -ArgumentList `
        "--start-maximized", `
        "--no-first-run", `
        "--no-default-browser-check", `
        "--disable-fre", `
        "https://signup.live.com"

    # Step 1: Email Page
    if (Wait-ForText -TargetText "Create your Microsoft account" -MaxRetries 15) {
        Invoke-LeftClick -X 516 -Y 362
        Send-AccountLineViaClipboard -LineNumber 1
        Invoke-LeftClick -X 516 -Y 450
    }

    # Step 2: Password Page
    if (Wait-ForText -TargetText "Create your password" -MaxRetries 15) {
        Invoke-LeftClick -X 372 -Y 435
        Send-AccountLineViaClipboard -LineNumber 2
        Invoke-LeftClick -X 359 -Y 539
    }

    # Step 3: Birthdate Page
    if (Wait-ForText -TargetText "Add some details" -MaxRetries 15) {
        Invoke-LeftClick -X 351 -Y 464
        [System.Windows.Forms.SendKeys]::SendWait("{DOWN}{ENTER}")
        
        Invoke-LeftClick -X 471 -Y 464
        [System.Windows.Forms.SendKeys]::SendWait("{DOWN}{ENTER}")

        Invoke-LeftClick -X 602 -Y 464
        Send-AccountLineViaClipboard -LineNumber 3

        Invoke-LeftClick -X 351 -Y 639
    }

    Write-Log "All steps executed successfully. Holding screen for 10s..."
    Start-Sleep -Seconds 10

} catch {
    Write-Log "Fatal Error encountered during execution: $_"
} finally {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
    Write-Log "Background screenshot job stopped."
    Write-Log "================ Automation Task Finished ================"
}
