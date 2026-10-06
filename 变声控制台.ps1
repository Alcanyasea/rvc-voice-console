# 变声控制台 - RVC 游戏变声托盘工具
# 打开面板 = 自动进入变声模式; 退出面板 = 自动恢复原声
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- 单实例 ----------
$mutex = New-Object System.Threading.Mutex($false, 'Local\RVCVoicePanel')
$acquired = $false
try { $acquired = $mutex.WaitOne(0, $false) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
# 上个实例被强杀会留下 abandoned mutex，此时所有权其实已拿到，直接继续；否则面板永远起不来
if (-not $acquired) { exit }

# ---------- COM: 切换/查询系统默认麦克风 ----------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace AudioSwitch {
    public enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow dataFlow, uint dwStateMask, out IntPtr ppDevices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string pwstrId, out IMMDevice ppDevice);
        int RegisterEndpointNotificationCallback(IntPtr pClient);
        int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppwstrId);
        int GetState(out uint pdwState);
    }

    [Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPolicyConfig {
        int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, out IntPtr ppFormat);
        int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, int bDefault, out IntPtr ppFormat);
        int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId);
        int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, IntPtr pEndpointFormat, IntPtr pMixFormat);
        int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, int bDefault, out IntPtr pDefaultPeriod, out IntPtr pMinimumPeriod);
        int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, IntPtr pPeriod);
        int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, out IntPtr pMode);
        int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, IntPtr pMode);
        int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, int bFxStore, ref IntPtr key, ref IntPtr pv);
        int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, int bFxStore, ref IntPtr key, ref IntPtr pv);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, ERole eRole);
        int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string wzDeviceId, int bVisible);
    }

    public static class Policy {
        [DllImport("ole32.dll")]
        public static extern int CoInitializeEx(IntPtr pvReserved, uint dwCoInit);
        [DllImport("ole32.dll")]
        public static extern int CoCreateInstance(ref Guid rclsid, IntPtr pUnkOuter, uint dwClsContext, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        static readonly Guid CLSID_PolicyConfigClient = new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9");
        static readonly Guid IID_IPolicyConfig = new Guid("F8679F50-850A-41CF-9C72-430F290290C8");

        public static string DefaultCaptureId(ERole role) {
            IMMDevice dev;
            int hr = ((IMMDeviceEnumerator)new MMDeviceEnumeratorComObject()).GetDefaultAudioEndpoint(EDataFlow.eCapture, role, out dev);
            Marshal.ThrowExceptionForHR(hr);
            string id;
            dev.GetId(out id);
            return id;
        }

        public static void SetDefaultEndpoint(string deviceId, ERole role) {
            Guid clsid = CLSID_PolicyConfigClient;
            Guid iid = IID_IPolicyConfig;
            object o;
            int hr = CoCreateInstance(ref clsid, IntPtr.Zero, 0x17, ref iid, out o);
            Marshal.ThrowExceptionForHR(hr);
            int hr2 = ((IPolicyConfig)o).SetDefaultEndpoint(deviceId, role);
            Marshal.ThrowExceptionForHR(hr2);
        }
    }
}
"@

[AudioSwitch.Policy]::CoInitializeEx([IntPtr]::Zero, 0) | Out-Null

# ---------- RVC 运行检测（枚举窗口标题，pythonw 主窗口是托盘件标题不可靠） ----------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class RvcWindowProbe {
    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")]
    static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    static extern bool SetForegroundWindow(IntPtr hWnd);

    delegate bool EnumProc(IntPtr hWnd, IntPtr lp);

    public static bool AnyWindowStartsWith(string prefix, uint[] pids) {
        bool found = false;
        EnumWindows((h, lp) => {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) >= 0) {
                var sb = new StringBuilder(64);
                GetWindowText(h, sb, 64);
                if (sb.ToString().StartsWith(prefix)) { found = true; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    // 把 RVC 已隐藏/最小化的窗口调回前台（点 X 会收进托盘，用户看不到窗口不等于没在运行）
    public static bool RestoreWindowStartsWith(string prefix, uint[] pids) {
        bool found = false;
        EnumWindows((h, lp) => {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) >= 0) {
                var sb = new StringBuilder(64);
                GetWindowText(h, sb, 64);
                if (sb.ToString().StartsWith(prefix)) {
                    ShowWindowAsync(h, 9); // SW_RESTORE
                    SetForegroundWindow(h);
                    found = true;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

function Test-RvcRunning {
    $pids = @(Get-Process python, pythonw -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
    if ($pids.Count -eq 0) { return $false }
    return [RvcWindowProbe]::AnyWindowStartsWith('RVC', [uint32[]]$pids)
}

# ---------- 常量 ----------
$RVC_DIR   = 'D:\voice change\RVC2026\RVC20260718Nvidia'

function Get-EndpointMap {
    Get-PnpDevice -Class AudioEndpoint -Status OK | ForEach-Object {
        $id = $_.InstanceId -replace '^SWD\\MMDEVAPI\\', ''
        [pscustomobject]@{ Id = $id; Name = $_.FriendlyName; IsCapture = $id.StartsWith('{0.0.1.') }
    }
}

$map = Get-EndpointMap
$devCable = $map | Where-Object { $_.IsCapture -and $_.Name -like '*CABLE Output*' } | Select-Object -First 1
$devMic   = $map | Where-Object { $_.IsCapture -and $_.Name -like '*Misiom-Gaming Center*' } | Select-Object -First 1
if (-not $devCable -or -not $devMic) {
    [System.Windows.Forms.MessageBox]::Show('找不到 CABLE 虚拟声卡或 Misiom 麦克风，请确认设备已安装。', '变声控制台') | Out-Null
    exit
}

# ---------- 状态 ----------
$script:reallyExit = $false
$script:balloonShown = $false
$script:lastRvcRunning = $false

function Set-Mode([string]$mode) {
    $dev = if ($mode -eq 'game') { $devCable } else { $devMic }
    foreach ($r in [Enum]::GetValues([AudioSwitch.ERole])) {
        [AudioSwitch.Policy]::SetDefaultEndpoint($dev.Id, $r)
    }
}

function Start-RvcSilent {
    if (Test-RvcRunning) { return $false }
    Start-Process -FilePath (Join-Path $RVC_DIR 'runtime\pythonw.exe') `
        -ArgumentList '-I', 'realtime_guiw.pyw' `
        -WorkingDirectory $RVC_DIR -WindowStyle Hidden
    return $true
}

function Update-Status {
    try {
        $id  = [AudioSwitch.Policy]::DefaultCaptureId([AudioSwitch.ERole]::eCommunications)
        $rvc = Test-RvcRunning
        # RVC 转换流检测：读 RVC 开流/停流时写的状态文件（日志在静音时不增长，不可靠）
        $streaming = $false
        $stateFile = Join-Path $RVC_DIR 'stream_state.txt'
        if ($rvc -and (Test-Path $stateFile)) {
            $streaming = ((Get-Content $stateFile -Raw -ErrorAction SilentlyContinue) -eq 'running')
        }
        if ($id -eq $devCable.Id) {
            if ($rvc -and $streaming) {
                $script:lblStatus.Text = '● 变声生效中（RVC 转换运行中）'
                $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(166,227,161)
            } elseif ($rvc) {
                $script:lblStatus.Text = '● 变声已启用但无声 —— 请在 RVC 窗口点「开始音频转换」！'
                $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(250,179,135)
            } else {
                $script:lblStatus.Text = '● 变声已启用，但 RVC 未运行 —— 点下方「启动 RVC」！'
                $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(250,179,135)
            }
        } elseif ($id -eq $devMic.Id) {
            $script:lblStatus.Text = '● 原声模式（真实麦克风）'
            $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(137,180,250)
        } else {
            $name = ($map | Where-Object Id -eq $id | Select-Object -First 1).Name
            $script:lblStatus.Text = "● 当前默认麦克风: $name"
            $script:lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(166,173,200)
        }
        $script:lblRvc.Text = 'RVC: ' + $(if ($rvc -and $streaming) { '运行中 · 转换中' } elseif ($rvc) { '运行中 · 未开始转换' } else { '未运行' })
        # 变声模式下 RVC 从有到无 → 气泡提醒，避免游戏里莫名没声却不知道原因
        if ($script:lastRvcRunning -and -not $rvc -and $id -eq $devCable.Id) {
            $tray.BalloonTipTitle = '变声控制台'
            $tray.BalloonTipText = 'RVC 已退出，游戏里会没声 —— 点面板上的「启动 RVC」重启。'
            $tray.ShowBalloonTip(3000)
        }
        $script:lastRvcRunning = $rvc
    } catch { }
}

# ---------- 托盘图标 ----------
$bmp = New-Object System.Drawing.Bitmap 32, 32
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$circle = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(203,166,247))
$g.FillEllipse($circle, 1, 1, 30, 30)
$font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$g.DrawString('声', $font, [System.Drawing.Brushes]::White, 4, 3)
$g.Dispose()
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $icon
$tray.Text = '变声控制台'
$tray.Visible = $true

# ---------- 界面 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = '变声控制台'
$form.Size = New-Object System.Drawing.Size(340, 240)
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(0, ([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 280))
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(30,30,46)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = '游戏麦克风切换'
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(205,214,244)
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(16, 44)
$lblStatus.Size = New-Object System.Drawing.Size(296, 40)
$lblStatus.ForeColor = [System.Drawing.Color]::Gainsboro
$lblStatus.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.Controls.Add($lblStatus)

function New-Button([string]$text, [System.Drawing.Color]$back, [int]$x, [int]$y, [int]$w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 34)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $back
    $b.ForeColor = [System.Drawing.Color]::FromArgb(30,30,46)
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = 'Hand'
    $form.Controls.Add($b)
    return $b
}

$btnGame = New-Button '游戏变声' ([System.Drawing.Color]::FromArgb(166,227,161)) 16 90 136
$btnVoice = New-Button '恢复原声' ([System.Drawing.Color]::FromArgb(137,180,250)) 160 90 136
$btnRvc = New-Button '启动 RVC' ([System.Drawing.Color]::FromArgb(249,226,175)) 16 130 136

$lblRvc = New-Object System.Windows.Forms.Label
$lblRvc.Location = New-Object System.Drawing.Point(160, 136)
$lblRvc.Size = New-Object System.Drawing.Size(150, 24)
$lblRvc.ForeColor = [System.Drawing.Color]::FromArgb(166,173,200)
$lblRvc.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.Controls.Add($lblRvc)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = '关闭窗口 = 最小化到托盘 · 退出托盘菜单 = 恢复原声'
$lblHint.Location = New-Object System.Drawing.Point(16, 172)
$lblHint.Size = New-Object System.Drawing.Size(296, 20)
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(108,112,134)
$lblHint.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$form.Controls.Add($lblHint)

# ---------- 托盘菜单 ----------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow  = $menu.Items.Add('显示面板')
$miGame  = $menu.Items.Add('游戏变声')
$miVoice = $menu.Items.Add('恢复原声')
[void]$menu.Items.Add('-')
$miExit  = $menu.Items.Add('退出（恢复原声并关闭 RVC）')
$tray.ContextMenuStrip = $menu

# ---------- 事件 ----------
$btnGame.Add_Click({  try { Set-Mode 'game' } catch { };  Update-Status })
$btnVoice.Add_Click({ try { Set-Mode 'voice' } catch { }; Update-Status })
$btnRvc.Add_Click({
    if (Test-RvcRunning) {
        # 已在运行 ≠ 没反应：把收进托盘的 RVC 窗口调回前台
        $pids = @(Get-Process python, pythonw -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
        $restored = $false
        try { $restored = [RvcWindowProbe]::RestoreWindowStartsWith('RVC', [uint32[]]$pids) } catch { }
        $tray.BalloonTipTitle = '变声控制台'
        $tray.BalloonTipText = if ($restored) { 'RVC 已在运行，窗口已调到前台。' } else { 'RVC 已在运行；找不到窗口就点任务栏托盘 "^" 里的 RVC 图标。' }
        $tray.ShowBalloonTip(1500)
    } else {
        Start-RvcSilent | Out-Null
        # 刚拉起的窗口要几秒才出现，先标记为在运行，防止 tick 误报"RVC 已退出"
        $script:lastRvcRunning = $true
    }
})

$miShow.Add_Click({  $form.Show(); $form.Activate() })
$miGame.Add_Click({  try { Set-Mode 'game' } catch { };  Update-Status })
$miVoice.Add_Click({ try { Set-Mode 'voice' } catch { }; Update-Status })
$miExit.Add_Click({
    $script:reallyExit = $true
    # 联动关闭 RVC：写退出标记让它走正常停流退出（最多等 3 秒），卡死就按 pid 强杀兜底。
    # 用进程判断而非窗口判断——RVC 还在加载（窗口未出现）时退出也要能关掉它
    try {
        $rvcPids = @(Get-Process python, pythonw -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
        if ($rvcPids.Count -gt 0) {
            Set-Content -LiteralPath (Join-Path $RVC_DIR 'panel_quit.flag') -Value 'quit' -Encoding ASCII
            $deadline = (Get-Date).AddSeconds(3)
            while ((Get-Date) -lt $deadline -and (Get-Process python, pythonw -ErrorAction SilentlyContinue | Where-Object { $rvcPids -contains $_.Id })) {
                Start-Sleep -Milliseconds 200
            }
            Get-Process python, pythonw -ErrorAction SilentlyContinue |
                Where-Object { $rvcPids -contains $_.Id } |
                Stop-Process -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    try { Set-Mode 'voice' } catch { }
    $form.Close()
})

$tray.Add_MouseUp({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible) { $form.Hide() } else { $form.Show(); $form.Activate() }
    }
})

$form.Add_FormClosing({
    param($s, $e)
    if (-not $script:reallyExit) {
        $e.Cancel = $true
        $form.Hide()
        if (-not $script:balloonShown) {
            $script:balloonShown = $true
            $tray.BalloonTipTitle = '变声控制台'
            $tray.BalloonTipText = '已最小化到托盘，变声仍在生效。点托盘图标可重新打开，退出时自动恢复原声。'
            $tray.ShowBalloonTip(2500)
        }
    }
})

$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.WindowState]::Minimized) { $form.Hide() }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Update-Status })
$timer.Start()

# ---------- 启动: 自动进入变声模式 + 拉起 RVC（已在运行则跳过） ----------
Set-Mode 'game'
Start-RvcSilent | Out-Null
# 刚拉起的 pythonw 窗口要几秒才出现，先标记为在运行，防止前几秒 tick 误报"RVC 已退出"
$script:lastRvcRunning = $true
$tray.BalloonTipTitle = '变声控制台'
$tray.BalloonTipText = '变声已启用，RVC 启动中（模型加载约 10 秒），转换会自动开始。'
$tray.ShowBalloonTip(2500)
Update-Status
[void][System.Windows.Forms.Application]::Run($form)

# ---------- 清理 ----------
$timer.Stop()
$tray.Visible = $false
$tray.Dispose()
