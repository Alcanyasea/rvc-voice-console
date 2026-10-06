param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('once', 'watch')]
    [string]$Mode
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace SessionScan {
    public enum EDataFlow { eRender = 0, eCapture = 1 }
    public enum ERole { eConsole = 0, eMultimedia = 1, eCommunications = 2 }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDevEnum { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow dataFlow, uint mask, out IntPtr devices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice dev);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice dev);
        int RegisterEndpointNotificationCallback(IntPtr cb);
        int UnregisterEndpointNotificationCallback(IntPtr cb);
    }
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceCollection {
        int GetCount(out uint count);
        int Item(uint index, out IMMDevice dev);
    }
    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr param, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        int OpenPropertyStore(int access, out IntPtr store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out uint state);
    }
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionManager2 {
        int GetAudioSessionControl(IntPtr guid, uint flags, out IntPtr ctl);
        int GetSimpleAudioVolume(IntPtr guid, uint flags, out IntPtr vol);
        int GetSessionEnumerator(out IAudioSessionEnumerator enumerator);
    }
    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionEnumerator {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl session);
    }
    [Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionControl2 {
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetProcessId(out uint pid);
        int IsSystemSoundsSession();
        int SetDuckingPreference(bool opt);
    }
    [Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioSessionControl {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr ctx);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, IntPtr ctx);
        int GetGroupingParam(out Guid guid);
        int SetGroupingParam(ref Guid guid, IntPtr ctx);
        int RegisterAudioSessionNotification(IntPtr notify);
        int UnregisterAudioSessionNotification(IntPtr notify);
    }

    public static class Scan {
        [DllImport("ole32.dll")] public static extern int CoInitializeEx(IntPtr pv, uint co);

        public static string[] ListDeviceIds(int flow) {
            var en = (IMMDeviceEnumerator)new MMDevEnum();
            IntPtr colPtr;
            int hr = en.EnumAudioEndpoints((EDataFlow)flow, 1, out colPtr);
            if (hr != 0) return new string[0];
            var col = (IMMDeviceCollection)Marshal.GetObjectForIUnknown(colPtr);
            uint count; col.GetCount(out count);
            var list = new string[count];
            for (uint i = 0; i < count; i++) {
                IMMDevice dev; col.Item(i, out dev);
                string id; dev.GetId(out id);
                list[i] = id;
            }
            return list;
        }

        // 返回该设备上目标进程的会话状态: null=无会话, "Active"/"Inactive"
        public static string FindPidSession(string deviceId, uint targetPid) {
            var en = (IMMDeviceEnumerator)new MMDevEnum();
            IMMDevice dev;
            if (en.GetDevice(deviceId, out dev) != 0) return null;
            Guid iidMgr = typeof(IAudioSessionManager2).GUID;
            object mgrObj;
            if (dev.Activate(ref iidMgr, 0x17, IntPtr.Zero, out mgrObj) != 0) return null;
            var mgr = (IAudioSessionManager2)mgrObj;
            IAudioSessionEnumerator enumr;
            if (mgr.GetSessionEnumerator(out enumr) != 0) return null;
            int count; enumr.GetCount(out count);
            for (int i = 0; i < count; i++) {
                IAudioSessionControl ctl;
                if (enumr.GetSession(i, out ctl) != 0) continue;
                var ctl2 = ctl as IAudioSessionControl2;
                if (ctl2 == null) continue;
                uint pid; ctl2.GetProcessId(out pid);
                if (pid != targetPid) continue;
                int state; ctl.GetState(out state);
                return (state == 1) ? "Active" : "Inactive";
            }
            return null;
        }
    }
}
"@

[SessionScan.Scan]::CoInitializeEx([IntPtr]::Zero, 0) | Out-Null

$nameMap = @{}
Get-PnpDevice -Class AudioEndpoint -Status OK | ForEach-Object {
    $nameMap[$_.InstanceId -replace '^SWD\\MMDEVAPI\\', ''] = $_.FriendlyName
}

function Get-GamePid {
    (Get-Process NarakaBladepoint -ErrorAction SilentlyContinue | Select-Object -First 1).Id
}

if ($Mode -eq 'once') {
    # 自检: RVC(pythonw) 的播放会话应出现在 CABLE Input 上
    $rvc = (Get-Process pythonw -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    if ($rvc) {
        $renderIds = [SessionScan.Scan]::ListDeviceIds(0)
        Write-Host ("自检: 渲染设备数=" + $renderIds.Length)
        foreach ($id in $renderIds) {
            $st = [SessionScan.Scan]::FindPidSession($id, [uint32]$rvc)
            if ($st) { Write-Host ("自检 OK: RVC 正在向 [{0}] 渲染 ({1})" -f $nameMap[$id], $st) }
        }
    }
    $gp = Get-GamePid
    if (-not $gp) { Write-Host "永劫未运行"; exit }
    Write-Host ("永劫 PID: " + $gp)
    $hit = $false
    foreach ($flow in 1, 0) {
        foreach ($id in [SessionScan.Scan]::ListDeviceIds($flow)) {
            $st = [SessionScan.Scan]::FindPidSession($id, [uint32]$gp)
            if ($st) {
                $hit = $true
                $dir = if ($flow -eq 1) { '采集(麦克风)' } else { '渲染(扬声器)' }
                Write-Host ("★ 永劫 [{0}]: {1} - {2}" -f $dir, $nameMap[$id], $st)
            }
        }
    }
    if (-not $hit) { Write-Host "此瞬间未捕捉到永劫的音频会话（按键说话需按住键时扫）" }
    exit
}

# ---------- watch 模式: 持续监听 90 秒 ----------
Write-Host "监听中(90秒)... 请按住语音键持续说话"
$deadline = (Get-Date).AddSeconds(90)
$seen = @{}
while ((Get-Date) -lt $deadline) {
    $gp = Get-GamePid
    if ($gp) {
        foreach ($id in [SessionScan.Scan]::ListDeviceIds(1)) {
            $st = [SessionScan.Scan]::FindPidSession($id, [uint32]$gp)
            if ($st -eq 'Active') {
                $key = "$id"
                if (-not $seen[$key]) {
                    $seen[$key] = $true
                    Write-Host ("[{0:HH:mm:ss}] ★ 抓到! 永劫正在从 [{1}] 采集声音" -f (Get-Date), $nameMap[$id])
                }
            }
        }
    }
    Start-Sleep -Milliseconds 250
}
if ($seen.Count -eq 0) { Write-Host "90秒内未捕捉到采集会话 - 语音键没按住或游戏语音未开" }
else { Write-Host "扫描完成, 结论如上" }
