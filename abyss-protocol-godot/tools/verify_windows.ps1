param(
    [string]$ExecutablePath = (Join-Path $PSScriptRoot 'AbyssProtocol.exe'),
    [string]$OutputDirectory = ([IO.Path]::GetTempPath()),
    [switch]$Rendered,
    [ValidateSet('opengl3', 'opengl3_angle')][string]$Renderer = 'opengl3',
    [string]$WinePath = '',
    [string]$WinePrefix = ''
)

$ErrorActionPreference = 'Stop'
$nativeWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $nativeWindows -and -not $WinePath) {
    throw 'Run on Windows, or provide -WinePath for explicitly labeled compatibility testing.'
}
$executable = (Resolve-Path -LiteralPath $ExecutablePath).Path
$pack = [IO.Path]::ChangeExtension($executable, '.pck')
if (-not (Test-Path -LiteralPath $pack -PathType Leaf)) { throw 'Missing game content pack.' }
$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('abyss-windows-' + [Guid]::NewGuid().ToString('N'))
$fixture = Join-Path $runDirectory 'storage with spaces'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture '.abyss-release-fixture') -Value 'Disposable verification data' -Encoding UTF8
$isolatedWinePrefix = Join-Path $runDirectory 'wine-prefix'
if ($WinePrefix) {
    $isolatedWinePrefix = [IO.Path]::GetFullPath($WinePrefix)
    if (-not (Test-Path -LiteralPath (Join-Path $isolatedWinePrefix '.abyss-wine-fixture'))) {
        throw 'Reusing Wine requires an explicitly marked .abyss-wine-fixture prefix.'
    }
}

function Get-GuestPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path).Replace('\', '/')
    if ($WinePath) { return 'Z:' + $absolute }
    return $absolute
}

function Quote-Argument([string]$Value) {
    # Windows CRT quoting, including spaces and any trailing backslashes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

$checks = @()
try {
    foreach ($stage in @('campaign', 'write', 'read')) {
        $engineLog = Join-Path $runDirectory ($stage + '.engine.log')
        $arguments = @('--audio-driver', 'Dummy', '--log-file', (Get-GuestPath $engineLog))
        if (-not $Rendered) { $arguments += '--headless' }
        else { $arguments += @('--rendering-driver', $Renderer) }
        $arguments += @('--', '--verify-release')
        if ($stage -ne 'campaign') {
            $arguments += @("--verify-storage=$(Get-GuestPath $fixture)", "--verify-stage=$stage")
        }
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $executable
        if ($WinePath) {
            $start.FileName = (Resolve-Path -LiteralPath $WinePath).Path
            $arguments = @($executable) + $arguments
            $start.EnvironmentVariables['WINEPREFIX'] = $isolatedWinePrefix
            $start.EnvironmentVariables['WINEDEBUG'] = '-all'
            $start.EnvironmentVariables['MVK_CONFIG_LOG_LEVEL'] = '0'
            $start.EnvironmentVariables['WINEDLLOVERRIDES'] = 'winemenubuilder.exe=d;mscoree,mshtml=d'
        }
        $start.Arguments = ($arguments | ForEach-Object { Quote-Argument $_ }) -join ' '
        $start.WorkingDirectory = $runDirectory
        $start.UseShellExecute = $false
        $start.CreateNoWindow = -not $Rendered
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $start
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timeout = if ($WinePath -and $stage -eq 'campaign') { 300000 } else { 90000 }
        if (-not $process.WaitForExit($timeout)) {
            $process.Kill()
            throw "Verification timed out during $stage. Logs: $runDirectory"
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        if (Test-Path -LiteralPath $engineLog) { $log += Get-Content -LiteralPath $engineLog -Raw -Encoding UTF8 }
        Set-Content -LiteralPath (Join-Path $runDirectory ($stage + '.log')) -Value $log -Encoding UTF8
        $prefix = if ($stage -eq 'campaign') { 'ABYSS RELEASE' } else { 'ABYSS STORAGE ' + $stage.ToUpperInvariant() }
        $summary = [regex]::Match($log, [regex]::Escape($prefix) + ': \d+ checks, 0 failures')
        if ($process.ExitCode -ne 0 -or $log.Contains('ERROR:') -or -not $summary.Success) {
            throw "Verification failed during $stage (exit $($process.ExitCode)). Logs: $runDirectory"
        }
        $checks += @{ stage = $stage; summary = $summary.Value; exit_code = $process.ExitCode }
        Write-Output $summary.Value
        $process.Dispose()
    }
    $report = @{
        runtime = $(if ($WinePath) { 'Wine compatibility; not Windows hardware' } else { 'Windows native' })
        host_os = [Environment]::OSVersion.VersionString
        rendered = [bool]$Rendered
        requested_renderer = $(if ($Rendered) { $Renderer } else { 'headless' })
        executable_sha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        content_sha256 = (Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash.ToLowerInvariant()
        checks = $checks
        player_saves = 'Untouched; marked temporary fixture in a separate working directory'
    }
    $reportPath = Join-Path $runDirectory 'report.json'
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Output ('ABYSS WINDOWS REPORT: ' + $reportPath)
} finally {
    # Keep disposable data and logs for diagnosis. Never delete player data.
    Write-Output ('Verification directory: ' + $runDirectory)
}
