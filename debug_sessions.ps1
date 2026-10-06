Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace SessDbg {
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
        int GetSessionEnumerator(out IAudioSessionEnumerator e);
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
        int RegisterAudioSessionNotification(IntPtr n);
        int UnregisterAudioSessionNotification(IntPtr n);
    }

    public static class Dbg {
        [DllImport("ole32.dll")] public static extern int CoInitializeEx(IntPtr pv, uint co);

        public static int HrGetMgr(string deviceId, out object mgr) {
            var en = (IMMDeviceEnumerator)new MMDevEnum();
            IMMDevice dev;
            int hr = en.GetDevice(deviceId, out dev);
            if (hr != 0) { mgr = null; return hr; }
            Guid iid = typeof(IAudioSessionManager2).GUID;
            return dev.Activate(ref iid, 0x17, IntPtr.Zero, out mgr);
        }
        public static int HrGetSessions(object mgrObj, out IAudioSessionEnumerator e) {
            var mgr = (IAudioSessionManager2)mgrObj;
            return mgr.GetSessionEnumerator(out e);
        }
        public static int HrGetCount(IAudioSessionEnumerator e, out int count) { return e.GetCount(out count); }
        public static int HrGetSession(IAudioSessionEnumerator e, int i, out IAudioSessionControl c) { return e.GetSession(i, out c); }
        public static int HrGetPid(IAudioSessionControl c, out uint pid) {
            var c2 = (IAudioSessionControl2)c;
            return c2.GetProcessId(out pid);
        }
        public static int HrGetState(IAudioSessionControl c, out int state) { return c.GetState(out state); }

        // 全程在 C# 内完成枚举，避开 PowerShell 的 COM 类型边界
        public static string DumpSessions(string deviceId) {
            try {
                var en = (IMMDeviceEnumerator)new MMDevEnum();
                IMMDevice dev;
                int hr = en.GetDevice(deviceId, out dev);
                if (hr != 0) return "GetDevice失败: 0x" + hr.ToString("X8");
                Guid iid = typeof(IAudioSessionManager2).GUID;
                object mgrObj;
                hr = dev.Activate(ref iid, 0x17, IntPtr.Zero, out mgrObj);
                if (hr != 0) return "Activate失败: 0x" + hr.ToString("X8");
                var mgr = (IAudioSessionManager2)mgrObj;
                IAudioSessionEnumerator e;
                hr = mgr.GetSessionEnumerator(out e);
                if (hr != 0) return "GetSessionEnumerator失败: 0x" + hr.ToString("X8");
                int count;
                hr = e.GetCount(out count);
                if (hr != 0) return "GetCount失败: 0x" + hr.ToString("X8");
                var lines = new System.Collections.Generic.List<string>();
                lines.Add("会话数=" + count);
                for (int i = 0; i < count; i++) {
                    IAudioSessionControl c;
                    if (e.GetSession(i, out c) != 0) { lines.Add("会话[" + i + "]获取失败"); continue; }
                    if (c == null) { lines.Add("会话[" + i + "]=null"); continue; }
                    var c2 = (IAudioSessionControl2)c;
                    uint pid;
                    c2.GetProcessId(out pid);
                    int state;
                    c.GetState(out state);
                    string sessId;
                    c2.GetSessionIdentifier(out sessId);
                    // 会话标识符里含有拥有进程的 exe 完整路径
                    string owner = "?";
                    if (!string.IsNullOrEmpty(sessId)) {
                        int p = sessId.LastIndexOf('%');
                        string pathPart = sessId;
                        if (p >= 0) pathPart = sessId.Substring(0, p);
                        int bs = pathPart.LastIndexOf('\\');
                        if (bs >= 0) owner = pathPart.Substring(bs + 1);
                    }
                    lines.Add(string.Format("会话[{0}]: pid={1} state={2} 拥有者={3}", i, pid, state, owner));
                }
                return string.Join(" | ", lines);
            } catch (Exception ex) {
                return "异常: " + ex.Message;
            }
        }
    }
}
"@

[SessDbg.Dbg]::CoInitializeEx([IntPtr]::Zero, 0) | Out-Null
# 找 CABLE Input 渲染设备
$map = @{}
Get-PnpDevice -Class AudioEndpoint -Status OK | ForEach-Object { $map[$_.InstanceId -replace '^SWD\\MMDEVAPI\\', ''] = $_.FriendlyName }
$cableId = $map.Keys | Where-Object { $_.StartsWith('{0.0.0.') -and $map[$_] -like '*VB-Audio Virtual Cable*' } | Select-Object -First 1
Write-Host ("CABLE Input: " + $map[$cableId])
Write-Host ([SessDbg.Dbg]::DumpSessions($cableId))
Write-Host "=== 全部设备的全部会话 ==="
foreach ($id in $map.Keys) {
    $dump = [SessDbg.Dbg]::DumpSessions($id)
    if ($dump -notmatch '会话数=0') {
        Write-Host ("[{0}]" -f $map[$id])
        Write-Host ("   " + $dump)
    }
}
