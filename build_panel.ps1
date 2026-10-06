$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$dir = 'D:\voice change'

# ---------- 1. 生成托盘/程序图标 .ico ----------
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$circle = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(203,166,247))
$g.FillEllipse($circle, 1, 1, 30, 30)
$font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$g.DrawString('声', $font, [System.Drawing.Brushes]::White, 4, 3)
$g.Dispose()
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$icoPath = Join-Path $dir '变声控制台.ico'
$fs = [System.IO.File]::Create($icoPath)
$icon.Save($fs)
$fs.Close()
$pngPath = Join-Path $dir '变声控制台.png'
$bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "icon: $icoPath / $pngPath"

# ---------- 2. 生成启动器源码 ----------
$csPath = Join-Path $dir 'panel_launcher.cs'
$ps1cs = (Join-Path $dir '变声控制台.ps1').Replace('\', '\\')
$cs = @"
using System;
using System.Diagnostics;

static class Launcher {
    [STAThread]
    static void Main() {
        var psi = new ProcessStartInfo {
            FileName = "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"$ps1cs\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        Process.Start(psi);
    }
}
"@
[System.IO.File]::WriteAllText($csPath, $cs, [System.Text.Encoding]::UTF8)
Write-Host "source: $csPath"

# ---------- 3. csc 编译为 WinExe（无控制台子系统） ----------
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exePath = Join-Path $dir '变声控制台.exe'
& $csc /nologo /target:winexe /out:"$exePath" /win32icon:"$icoPath" "$csPath"
if ($LASTEXITCODE -ne 0) { throw "csc failed: $LASTEXITCODE" }
Write-Host "exe: $exePath"

# ---------- 4. 更新桌面 + 开始菜单快捷方式指向 exe ----------
$ws = New-Object -ComObject WScript.Shell
foreach ($base in @([Environment]::GetFolderPath('Desktop'), "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")) {
    $lnk = $ws.CreateShortcut((Join-Path $base '变声控制台.lnk'))
    $lnk.TargetPath = $exePath
    $lnk.Arguments = ''
    $lnk.IconLocation = "$exePath,0"
    $lnk.Description = '游戏变声托盘控制台：打开即变声，退出即恢复原声'
    $lnk.Save()
    Write-Host "shortcut updated: $base"
}
