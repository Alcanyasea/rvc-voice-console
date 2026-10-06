using System;
using System.Diagnostics;

static class Launcher {
    [STAThread]
    static void Main() {
        var psi = new ProcessStartInfo {
            FileName = "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"D:\\voice change\\变声控制台.ps1\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        Process.Start(psi);
    }
}