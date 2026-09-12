# Source template only. Generate a version-bound handoff with prepare_windows_acceptance.py.
# Deploy the generated script beside the extracted game folder, outside its verified payload.
param(
    [switch]$ReportOnly,
    [string]$RunDirectory = '',
    [string]$DestinationRoot = '__ABYSS_REPORT_ROOT__'
)

$ErrorActionPreference = 'Stop'
$AcceptanceVersion = '__ABYSS_VERSION__'
if ($AcceptanceVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw 'This is an unrendered acceptance template. Run prepare_windows_acceptance.py against the local Windows build report first.'
}

function New-AcceptanceWorkspace([string[]]$Candidates) {
    $failures = @()
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $absolute = [IO.Path]::GetFullPath($candidate)
            if ($absolute.StartsWith('\\')) { throw 'A local directory is required.' }
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($absolute))
                if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'A local fixed disk is required.' }
            }
            $workspace = Join-Path $absolute ('abyss-acceptance-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $workspace | Out-Null
            # Verify the create/write/rename operations needed by isolated save transactions.
            $probe = Join-Path $workspace '.write-probe'
            [IO.File]::WriteAllText($probe, 'Disposable acceptance workspace')
            [IO.File]::Move($probe, (Join-Path $workspace '.abyss-acceptance-workspace'))
            return $workspace
        } catch {
            $failures += "$candidate : $($_.Exception.Message)"
        }
    }
    throw ('无法创建可写的本地验收目录。' + [Environment]::NewLine + ($failures -join [Environment]::NewLine))
}

function Publish-AcceptanceEvidence([string]$RunDirectory, [string]$DestinationRoot) {
    $runName = Split-Path -Leaf $RunDirectory
    if ($runName -notmatch '^abyss-windows-[0-9a-f]{32}$') { throw 'Unexpected verification directory name.' }
    $evidence = @('report.json')
    foreach ($stage in @('campaign', 'write', 'read')) {
        $evidence += "$stage.log", "$stage.engine.log"
    }
    foreach ($shot in @('title-write', 'title-read', 'shop-write', 'shop-read', 'victory-read', 'coop-write', 'coop-read')) {
        $evidence += "storage with spaces/$shot.png"
    }
    # Build a shareable local copy first. Never include profile/settings files.
    $local = Join-Path $RunDirectory ('diagnostics-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $local | Out-Null
    foreach ($relative in $evidence) {
        $source = Join-Path $RunDirectory $relative
        $item = Get-Item -LiteralPath $source
        $parent = Get-Item -LiteralPath (Split-Path -Parent $source)
        if (($item.Attributes -bor $parent.Attributes) -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Unexpected evidence link.'
        }
        $target = Join-Path $local $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath $source -Destination $target
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
            throw "Local evidence copy failed integrity verification: $relative"
        }
    }
    $receipt = @{
        version = $AcceptanceVersion
        copied_at_utc = [DateTime]::UtcNow.ToString('o')
        report_sha256 = (Get-FileHash -LiteralPath (Join-Path $local 'report.json')).Hash.ToLowerInvariant()
        scope = 'Automated Windows release verification. Physical controllers and human playtesting are not certified by this report.'
    }
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'handoff.json') -Encoding UTF8
    # Package only the whitelist copy, never the full test fixture or player saves.
    $archive = $local + '.zip'
    $archiveError = ''
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($local, $archive)
    } catch {
        $archiveError = $_.Exception.Message
        $archive = ''
    }
    $archiveName = "Windows验收报告-$AcceptanceVersion-$runName"
    $destination = Join-Path $DestinationRoot ($archiveName + '.zip')
    $operation = '检查报告目标目录'
    $target = $destination
    try {
        if (-not $archive) { throw ('无法生成报告 ZIP：' + $archiveError) }
        if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
            throw '报告目标目录不存在。请指定已有的可写目录。'
        }
        # A single file goes directly into the selected directory. Do not require
        # create-subdirectory or rename permissions on the receiving share.
        # Preserve both completed archives and interrupted uploads.
        if (Test-Path -LiteralPath $destination) {
            $destination = Join-Path $DestinationRoot ($archiveName + '-retry-' + [Guid]::NewGuid().ToString('N') + '.zip')
        }
        $target = $destination
        $operation = '复制报告 ZIP'
        [IO.File]::Copy($archive, $destination, $false)
        $operation = '回读校验报告 ZIP'
        if ((Get-FileHash -LiteralPath $archive).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            throw 'Report ZIP upload failed integrity verification.'
        }
        return @{ published = $true; destination = $destination; local_directory = $local; local_archive = $archive; archive_error = $archiveError; error = '' }
    } catch {
        return @{ published = $false; destination = $destination; local_directory = $local; local_archive = $archive; archive_error = $archiveError; error = "$operation ($target): $($_.Exception.Message)" }
    }
}

function Read-AcceptanceReport([string]$RunDirectory, [hashtable]$Expected) {
    $directory = Get-Item -LiteralPath $RunDirectory
    $reportPath = Join-Path $RunDirectory 'report.json'
    $item = Get-Item -LiteralPath $reportPath
    if (-not $directory.PSIsContainer -or $item.PSIsContainer -or
        (($directory.Attributes -bor $item.Attributes) -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Unexpected report link or file type.'
    }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($report.runtime -ne 'Windows native' -or $report.rendered -ne $true -or
        $report.executable_sha256 -ne $Expected['AbyssProtocol.exe'] -or
        $report.content_sha256 -ne $Expected['AbyssProtocol.pck'] -or $report.checks.Count -ne 3) {
        throw 'The report does not verify this rendered Windows release.'
    }
    foreach ($stage in @('campaign', 'write', 'read')) {
        $matching = @($report.checks | Where-Object { $_.stage -eq $stage })
        if ($matching.Count -ne 1 -or $matching[0].exit_code -ne 0 -or $matching[0].summary -notmatch ': \d+ checks, 0 failures$') {
            throw "Incomplete verification stage: $stage"
        }
    }
    return $report
}

function Restore-AcceptanceEvidence([string[]]$Candidates, [hashtable]$Expected, [string]$DestinationRoot, [string]$RunDirectory = '') {
    if (-not $RunDirectory) {
        $reports = @()
        # Search only our marked local workspaces, with two bounded directory levels.
        foreach ($candidate in $Candidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            foreach ($workspace in (Get-ChildItem -LiteralPath $candidate -Directory -Filter 'abyss-acceptance-*' -ErrorAction SilentlyContinue)) {
                if ($workspace.Name -notmatch '^abyss-acceptance-[0-9a-f]{32}$' -or
                    ($workspace.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                $marker = Get-Item -LiteralPath (Join-Path $workspace.FullName '.abyss-acceptance-workspace') -Force -ErrorAction SilentlyContinue
                if (-not $marker -or $marker.PSIsContainer -or ($marker.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                foreach ($run in (Get-ChildItem -LiteralPath $workspace.FullName -Directory -Filter 'abyss-windows-*' -ErrorAction SilentlyContinue)) {
                    if ($run.Name -notmatch '^abyss-windows-[0-9a-f]{32}$') { continue }
                    try {
                        [void](Read-AcceptanceReport -RunDirectory $run.FullName -Expected $Expected)
                        $reports += Get-Item -LiteralPath (Join-Path $run.FullName 'report.json')
                    } catch { continue }
                }
            }
        }
        $latest = $reports | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (-not $latest) { throw '未找到本版已通过的 Windows 本地报告。请用 -RunDirectory 指定之前窗口显示的测试日志目录；不会自动重跑游戏。' }
        $RunDirectory = $latest.DirectoryName
    }
    $report = Read-AcceptanceReport -RunDirectory $RunDirectory -Expected $Expected
    Write-Host ('使用已有测试报告：' + (Join-Path $RunDirectory 'report.json'))
    Write-Host ('报告时间：' + (Get-Item -LiteralPath (Join-Path $RunDirectory 'report.json')).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    foreach ($check in $report.checks) { Write-Host $check.summary }
    $result = Publish-AcceptanceEvidence -RunDirectory $RunDirectory -DestinationRoot $DestinationRoot
    $result.run_directory = $RunDirectory
    return $result
}

$phase = '启动检查'
$temporary = $null
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This handoff must be run on the Windows test computer.'
    }
    if ($RunDirectory -and -not $ReportOnly) { throw '-RunDirectory requires -ReportOnly.' }
    Write-Host "Windows 验收工具 · $AcceptanceVersion / 修订 5"
    $phase = '核对发行文件'
    $package = Join-Path $PSScriptRoot ('深渊协议 ' + $AcceptanceVersion)
    $expected = @{
        'AbyssProtocol.exe' = '__ABYSS_EXE_SHA256__'
        'AbyssProtocol.pck' = '__ABYSS_PCK_SHA256__'
        'Verify-Windows.ps1' = '__ABYSS_VERIFIER_SHA256__'
    }
    foreach ($name in $expected.Keys) {
        $path = Join-Path $package $name
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected[$name]) {
            throw "Release file does not match verified version ${AcceptanceVersion}: $name"
        }
    }

    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $candidates = @([IO.Path]::GetTempPath())
    if ($localData) { $candidates += (Join-Path $localData 'AbyssProtocol-QA') }
    if (-not $DestinationRoot) { $DestinationRoot = $PSScriptRoot }
    Write-Host ('报告 ZIP 直接保存到：' + $DestinationRoot)
    if ($ReportOnly) {
        $phase = '整理已有验收报告'
        Write-Host '仅整理并回传已有报告，不启动游戏、不重复测试。'
        $publication = Restore-AcceptanceEvidence -Candidates $candidates -Expected $expected -DestinationRoot $DestinationRoot -RunDirectory $RunDirectory
        $runDirectory = $publication.run_directory
    } else {
        # Save transactions stay on the Windows local disk. The SMB share may deny renames.
        $phase = '创建本地测试目录'
        $temporary = New-AcceptanceWorkspace -Candidates $candidates
        Write-Host "本地验收目录：$temporary"
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $verifier = Join-Path $package 'Verify-Windows.ps1'
        $phase = '运行游戏自检'
        Write-Host "正在验证 ${AcceptanceVersion}：单人、双人、窗口渲染及跨进程续档。正式玩家存档不会被读写。"
        & $verifier -ExecutablePath (Join-Path $package 'AbyssProtocol.exe') -OutputDirectory $temporary -Rendered |
            ForEach-Object { $lines.Add([string]$_); Write-Host $_ }

        $phase = '核对自检结果'
        $markers = @($lines | Where-Object { $_.StartsWith('ABYSS WINDOWS REPORT: ') })
        if ($markers.Count -ne 1) { throw 'The verifier did not return exactly one completed report.' }
        $reportPath = [IO.Path]::GetFullPath($markers[0].Substring('ABYSS WINDOWS REPORT: '.Length))
        $runDirectory = Split-Path -Parent $reportPath
        $runName = Split-Path -Leaf $runDirectory
        if ($runName -notmatch '^abyss-windows-[0-9a-f]{32}$' -or
            -not [string]::Equals([IO.Path]::GetFullPath((Split-Path -Parent $runDirectory)).TrimEnd('\'), $temporary.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The returned report is outside the local verification fixture.'
        }
        [void](Read-AcceptanceReport -RunDirectory $runDirectory -Expected $expected)

        Write-Host '游戏自动测试已通过。'
        $phase = '保存和回传报告'
        $publication = Publish-AcceptanceEvidence -RunDirectory $runDirectory -DestinationRoot $DestinationRoot
    }
    Write-Host ('本地报告和截图：' + $publication.local_directory)
    if ($publication.local_archive) { Write-Host ('可直接转交的报告 ZIP：' + $publication.local_archive) }
    elseif ($publication.archive_error) { Write-Host ('ZIP 未生成，仍可转交上面的 diagnostics 目录：' + $publication.archive_error) }
    if ($publication.published) {
        Write-Host ('报告和截图已回传：' + $publication.destination)
    } else {
        Write-Host '游戏自动测试通过，但报告回传失败；本地结果已保留。' -ForegroundColor Yellow
        Write-Host ('回传目标：' + $publication.destination)
        Write-Host ('回传错误：' + $publication.error)
        Write-Host '请转交上面的报告 ZIP 或 diagnostics 目录。可双击“仅回传验收报告.cmd”补传，不需要管理员权限或重跑游戏。'
        if ($publication.local_archive) {
            try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $publication.local_archive + '"') | Out-Null }
            catch { Write-Host '未能打开资源管理器，请按上面的路径找到报告 ZIP。' }
        }
    }
    Write-Host '接下来仍需用两只实体手柄试玩，并检查 2560×1440 全屏、声音、断线恢复及操作手感。'
    if ($publication.published) { exit 0 }
    exit 2
} catch {
    Write-Host ("验收未完成（$phase）：" + $_.Exception.Message) -ForegroundColor Red
    if ($_.TargetObject) { Write-Host ('出错目标：' + $_.TargetObject) }
    Write-Host $_.InvocationInfo.PositionMessage
    if ($runDirectory) { Write-Host "测试日志目录：$runDirectory" }
    elseif ($temporary) { Write-Host "本地验收目录：$temporary" }
    Write-Host '请保留此窗口中的阶段、完整路径和错误信息。已有本地日志不会删除。'
    exit 1
}
