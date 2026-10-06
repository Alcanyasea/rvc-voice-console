param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('game', 'voice')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

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

        public static IPolicyConfig GetPolicyConfig() {
            Guid clsid = CLSID_PolicyConfigClient;
            Guid iid = IID_IPolicyConfig;
            object o;
            int hr = CoCreateInstance(ref clsid, IntPtr.Zero, 0x17, ref iid, out o);
            Marshal.ThrowExceptionForHR(hr);
            return (IPolicyConfig)o;
        }

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

$endpoints = Get-PnpDevice -Class AudioEndpoint -Status OK | ForEach-Object {
    $id = $_.InstanceId -replace '^SWD\\MMDEVAPI\\', ''
    [pscustomobject]@{ Id = $id; Name = $_.FriendlyName; IsCapture = $id.StartsWith('{0.0.1.') }
}

$patterns = @{ game = '*CABLE Output*'; voice = '*Misiom-Gaming Center*' }
$dev = $endpoints | Where-Object { $_.IsCapture -and $_.Name -like $patterns[$Mode] } | Select-Object -First 1
if (-not $dev) { throw "找不到匹配的录音设备: $($patterns[$Mode])" }

foreach ($role in [Enum]::GetValues([AudioSwitch.ERole])) {
    [AudioSwitch.Policy]::SetDefaultEndpoint($dev.Id, $role)
}

Start-Sleep -Milliseconds 400
Write-Host ("已切换系统默认麦克风 → {0}" -f $dev.Name)
foreach ($r in [Enum]::GetValues([AudioSwitch.ERole])) {
    $curId = [AudioSwitch.Policy]::DefaultCaptureId($r)
    $curName = ($endpoints | Where-Object Id -eq $curId | Select-Object -First 1).Name
    Write-Host ("  验证[{0}]: {1}" -f $r, $curName)
}
