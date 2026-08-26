# 引入 Windows API 与 .NET 绘图/输入程序集
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

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

    // 简单平滑移动到目标点
    public static void SmoothMove(int startX, int startY, int endX, int endY, int steps = 20) {
        Random rand = new Random();
        for (int i = 0; i <= steps; i++) {
            float t = (float)i / steps;
            int x = (int)(startX + (endX - startX) * t);
            int y = (int)(startY + (endY - startY) * t);
            SetCursorPos(x, y);
            Thread.Sleep(rand.Next(10, 20));
        }
    }

    // 模拟物理鼠标左键点击
    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        Thread.Sleep(100);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }
}
"@
Add-Type -TypeDefinition $APIs

function Write-Log {
    param([string]$Message)
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message"
}

# 1. 直接启动原生 Microsoft Edge 并最大化打开 Outlook 注册页
Write-Log "🚀 启动 Microsoft Edge 浏览器 (最大化)..."
Start-Process "msedge.exe" -ArgumentList "--start-maximized", "--no-first-run", "--no-default-browser-check", "https://signup.live.com/"

Write-Log "⏳ 等待 15 秒页面加载..."
Start-Sleep -Seconds 15

# 2. 鼠标平滑移动至中心坐标 (512, 384) 并点击
Write-Log "🎯 移动鼠标至中心坐标 (512, 384) 并点击..."
[WinAPI]::SmoothMove(100, 100, 512, 384, 25)
[WinAPI]::ClickAt(512, 384)
Start-Sleep -Seconds 1

# 3. 逐字模拟键盘输入完整邮箱
Write-Log "⌨️ 正在输入文本: abcd1234@outlook.com"
$text = "abcd1234@outlook.com"
foreach ($char in $text.ToCharArray()) {
    [System.Windows.Forms.SendKeys]::SendWait($char)
    Start-Sleep -Milliseconds (Get-Random -Minimum 60 -Maximum 120)
}
Start-Sleep -Seconds 3

# 4. 捕获屏幕并在 (512, 384) 绘制红星标记
Write-Log "📸 捕获屏幕并在 (512, 384) 标注红星..."
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

# 绘制红色准星
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Red, 2)
$cx = 512; $cy = 384; $r = 15
$graphics.DrawLine($pen, $cx - $r, $cy, $cx + $r, $cy)
$graphics.DrawLine($pen, $cx, $cy - $r, $cx, $cy + $r)
$graphics.DrawEllipse($pen, $cx - 5, $cy - 5, 10, 10)

$bmp.Save("$PSScriptRoot\abcd1234.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()

Write-Log "✅ 测试完成！截图已生成为 abcd1234.png。"
