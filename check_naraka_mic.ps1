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
        // 其余方法不调用，仅占位到可 QI 的程度
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

        public static string[] GetCaptureDevices() {
            var en = (IMMDeviceEnumerator)new MMDevEnum();
            IntPtr colPtr;
            int hr = en.EnumAudioEndpoints(EDataFlow.eCapture, 1, out colPtr);  // DEVICE_STATE_ACTIVE=1
            Marshal.ThrowExceptionForHR(hr);
            var col = (IMMDeviceCollection)Marshal.GetObjectForIUnknown(colPtr);
            uint count; col.GetCount(out count);
            var list = new string[count * 2];
            for (uint i = 0; i < count; i++) {
                IMMDevice dev; col.Item(i, out dev);
                string id; dev.GetId(out id);
                list[i * 2] = id;
                list[i * 2 + 1] = id;
            }
            return list;
        }

        public static void ScanPidOnDevice(string deviceId, uint targetPid, out string foundState) {
            foundState = null;
            var en = (IMMDeviceEnumerator)new MMDevEnum();
            IMMDevice dev;
            int hr = en.GetDevice(deviceId, out dev);
            if (hr != 0) return;
            Guid iidMgr = typeof(IAudioSessionManager2).GUID;
            object mgrObj;
            hr = dev.Activate(ref iidMgr, 0x17, IntPtr.Zero, out mgrObj);
            if (hr != 0) return;
            var mgr = (IAudioSessionManager2)mgrObj;
            IAudioSessionEnumerator enumr;
            hr = mgr.GetSessionEnumerator(out enumr);
            if (hr != 0) return;
            int count; enumr.GetCount(out count);
            for (int i = 0; i < count; i++) {
                IAudioSessionControl ctl;
                if (enumr.GetSession(i, out ctl) != 0) continue;
                var ctl2 = ctl as IAudioSessionControl2;
                if (ctl2 == null) continue;
                uint pid; ctl2.GetProcessId(out pid);
                if (pid != targetPid) continue;
                int state; ctl.GetState(out state);
                // 0=Inactive 1=Active
                foundState = (state == 1) ? "Active(正在采集)" : "Inactive(空闲)";
            }
        }
    }
}
"@

[SessionScan.Scan]::CoInitializeEx([IntPtr]::Zero, 0) | Out-Null

$game = Get-Process NarakaBladepoint -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { Write-Host "永劫无间未运行，进入游戏语音后我再扫描"; exit }
Write-Host ("永劫 PID: " + $game.Id)

$map = @{}
Get-PnpDevice -Class AudioEndpoint -Status OK | ForEach-Object {
    $map[$_.InstanceId -replace '^SWD\\MMDEVAPI\\', ''] = $_.FriendlyName
}

$devices = [SessionScan.Scan]::GetCaptureDevices()
$any = $false
for ($i = 0; $i -lt $devices.Length; $i += 2) {
    $id = $devices[$i]
    $name = $map[$id]
    if (-not $name) { continue }
    $state = $null
    [SessionScan.Scan]::ScanPidOnDevice($id, [uint32]$game.Id, [ref]$state)
    if ($state) {
        $any = $true
        Write-Host ("★ 永劫正在从 [{0}] 采集: {1}" -f $name, $state)
    }
}
if (-not $any) {
    Write-Host "未发现永劫的采集会话 —— 游戏语音未激活（需进组队/对局并开启语音，按键说话需按住键）"
}
