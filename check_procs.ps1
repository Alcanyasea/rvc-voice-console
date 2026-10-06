$procs = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'"
Write-Host ("python/pythonw 进程数: " + @($procs).Count)
foreach ($p in $procs) {
    $cl = if ($p.CommandLine) { $p.CommandLine.Substring(0, [Math]::Min(120, $p.CommandLine.Length)) } else { "(null)" }
    $win = ""
    $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
    if ($proc) { $win = $proc.MainWindowTitle }
    Write-Host ("PID " + $p.ProcessId + " [" + $p.Name + "] window='" + $win + "' : " + $cl)
}
