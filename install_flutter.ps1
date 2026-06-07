<#
    ============================================================
     Flutter SDK Installer  (PowerShell)
    ------------------------------------------------------------
     - Auto-detects the LATEST stable Flutter release
     - Resumable, retrying streaming download
     - Live animated progress bar (speed + ETA)
     - SHA-256 integrity verification against the official manifest
     - Robust extraction (tar.exe, fallback to .NET ZipArchive)
     - Idempotent: skips work that is already done
     - Adds Flutter to the system PATH (no duplicates)
    ============================================================
#>

[CmdletBinding()]
param(
    [string]$InstallRoot = $env:SystemDrive,   # Flutter extracts a "flutter" folder here -> C:\flutter
    [string]$Channel     = 'stable'
)

$ErrorActionPreference = 'Stop'
$script:Esc = [char]27

# ---------------------------------------------------------------
#  Console / color helpers
# ---------------------------------------------------------------

function Enable-VirtualTerminal {
    # Best-effort: enable ANSI VT processing on the classic console.
    try {
        $sig = @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
'@
        $k = Add-Type -MemberDefinition $sig -Name 'VtConsole' -Namespace 'Native' -PassThru -ErrorAction Stop
        $h = $k::GetStdHandle(-11)
        $mode = 0
        if ($k::GetConsoleMode($h, [ref]$mode)) {
            $null = $k::SetConsoleMode($h, $mode -bor 0x0004)  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
            return $true
        }
    } catch { }
    return $false
}

function C([string]$text, [int]$r, [int]$g, [int]$b) {
    if ($script:Vt) { return "$Esc[38;2;$r;$g;${b}m$text$Esc[0m" }
    return $text
}

function Write-Center([string]$text, [scriptblock]$colorize = $null) {
    $width = try { [Console]::WindowWidth } catch { 80 }
    $pad = [Math]::Max(0, [int](($width - $text.Length) / 2))
    $line = (' ' * $pad) + $text
    if ($colorize) { Write-Host (& $colorize $line) } else { Write-Host $line }
}

function Step([string]$msg)  { Write-Host (C "  ->  " 99 161 255) -NoNewline; Write-Host $msg }
function Ok([string]$msg)    { Write-Host (C "  OK  " 80 220 120) -NoNewline; Write-Host $msg }
function Warn([string]$msg)  { Write-Host (C "  !!  " 240 200 80) -NoNewline; Write-Host $msg }
function Fail([string]$msg)  { Write-Host (C "  XX  " 240 90 90) -NoNewline;  Write-Host $msg }

# ---------------------------------------------------------------
#  Banner
# ---------------------------------------------------------------

function Show-Banner {
    Clear-Host
    $art = @(
        '  ______ _       _   _            ',
        ' |  ____| |     | | | |           ',
        ' | |__  | |_   _| |_| |_ ___ _ __ ',
        ' |  __| | | | | | __| __/ _ \ ''__|',
        ' | |    | | |_| | |_| ||  __/ |   ',
        ' |_|    |_|\__,_|\__|\__\___|_|   '
    )
    Write-Host ''
    $n = $art.Count
    for ($i = 0; $i -lt $n; $i++) {
        # vertical blue -> cyan gradient
        $t = $i / [Math]::Max(1, ($n - 1))
        $r = [int](40  + (40  * $t))
        $g = [int](120 + (90  * $t))
        $b = [int](235 - (35  * $t))
        Write-Center $art[$i] { param($l) C $l $r $g $b }
    }
    Write-Host ''
    Write-Center '+--------------------------------------------------+' { param($l) C $l 90 110 140 }
    Write-Center '|        F L U T T E R   I N S T A L L E R         |' { param($l) C $l 120 200 255 }
    Write-Center '|     automated  *  verified  *  resumable         |' { param($l) C $l 150 160 180 }
    Write-Center '+--------------------------------------------------+' { param($l) C $l 90 110 140 }
    Write-Host ''
}

# ---------------------------------------------------------------
#  Helpers: size, progress bar, spinner
# ---------------------------------------------------------------

function Format-Size([double]$bytes) {
    if ($bytes -ge 1GB) { return ('{0:N2} GB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N1} MB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N0} KB' -f ($bytes / 1KB)) }
    return "$bytes B"
}

function Format-Time([double]$seconds) {
    if ($seconds -lt 0 -or [double]::IsInfinity($seconds) -or [double]::IsNaN($seconds)) { return '--:--' }
    $ts = [TimeSpan]::FromSeconds([Math]::Round($seconds))
    if ($ts.TotalHours -ge 1) { return ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds) }
    return ('{0:00}:{1:00}' -f $ts.Minutes, $ts.Seconds)
}

function Draw-ProgressBar {
    param(
        [double]$Fraction,           # 0..1
        [string]$Right = '',         # trailing text (speed / eta / sizes)
        [int]$Width = 34
    )
    $Fraction = [Math]::Max(0.0, [Math]::Min(1.0, $Fraction))
    $filled = [int]($Fraction * $Width)
    $empty  = $Width - $filled
    $pct    = ('{0,3:N0}%' -f ($Fraction * 100))

    try { [Console]::CursorLeft = 0 } catch { }
    Write-Host '   [' -NoNewline

    # color shifts green->cyan as it fills
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = 'Cyan'
    if ($filled -gt 0) { Write-Host ('#' * $filled) -NoNewline }
    [Console]::ForegroundColor = 'DarkGray'
    if ($empty  -gt 0) { Write-Host ('-' * $empty) -NoNewline }
    [Console]::ForegroundColor = $prev

    Write-Host "] " -NoNewline
    [Console]::ForegroundColor = 'White'
    Write-Host $pct -NoNewline
    [Console]::ForegroundColor = 'DarkGray'
    Write-Host ("  $Right") -NoNewline
    [Console]::ForegroundColor = $prev

    # pad to clear leftovers from previous longer lines
    Write-Host ('       ') -NoNewline
}

# ---------------------------------------------------------------
#  Manifest: discover latest release
# ---------------------------------------------------------------

function Get-LatestRelease {
    param([string]$Channel)

    $manifestUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $json = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing
    $targetHash = $json.current_release.$Channel
    if (-not $targetHash) { throw "Channel '$Channel' not found in release manifest." }

    # Prefer an architecture-specific build when available.
    $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'arm64' } else { 'x64' }

    $candidates = $json.releases | Where-Object { $_.hash -eq $targetHash -and $_.channel -eq $Channel }
    $rel = $candidates | Where-Object { $_.dart_sdk_arch -eq $arch } | Select-Object -First 1
    if (-not $rel) { $rel = $candidates | Select-Object -First 1 }
    if (-not $rel) { throw "Could not resolve a $Channel release from the manifest." }

    [pscustomobject]@{
        Version = $rel.version
        Url     = "$($json.base_url)/$($rel.archive)"
        Sha256  = $rel.sha256          # may be $null on older entries (handled gracefully)
        Arch    = $rel.dart_sdk_arch
    }
}

# ---------------------------------------------------------------
#  Download: resumable, retrying, animated
# ---------------------------------------------------------------

function Invoke-ResumableDownload {
    param(
        [string]$Url,
        [string]$Destination,
        [int]$MaxAttempts = 50
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $attempt = 0

    while ($true) {
        $attempt++
        $existing = 0
        if (Test-Path $Destination) { $existing = (Get-Item $Destination).Length }

        try {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.UserAgent = 'FlutterInstaller/1.0'
            $req.Timeout = 60000
            $req.ReadWriteTimeout = 60000
            if ($existing -gt 0) { $req.AddRange([long]$existing) }

            $resp = $req.GetResponse()
            $remaining = $resp.ContentLength
            $total = if ($existing -gt 0 -and $resp.StatusCode -eq 'PartialContent') { $existing + $remaining } else { $remaining }

            # If server ignored the range (returns 200), restart from scratch.
            if ($existing -gt 0 -and $resp.StatusCode -ne 'PartialContent') {
                $resp.Close()
                Remove-Item $Destination -Force -ErrorAction SilentlyContinue
                $existing = 0
                $req = [System.Net.HttpWebRequest]::Create($Url)
                $req.UserAgent = 'FlutterInstaller/1.0'
                $resp = $req.GetResponse()
                $total = $resp.ContentLength
            }

            $stream = $resp.GetResponseStream()
            $mode = if ($existing -gt 0) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
            $fs = [System.IO.FileStream]::new($Destination, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

            $buffer = New-Object byte[] (1MB)
            $downloaded = [long]$existing
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $lastTick = 0.0
            $lastBytes = $downloaded

            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
                $downloaded += $read

                $now = $sw.Elapsed.TotalSeconds
                if (($now - $lastTick) -ge 0.2) {
                    $instSpeed = ($downloaded - $lastBytes) / [Math]::Max(0.001, ($now - $lastTick))
                    $lastTick = $now
                    $lastBytes = $downloaded
                    $frac = if ($total -gt 0) { $downloaded / $total } else { 0 }
                    $eta  = if ($instSpeed -gt 0 -and $total -gt 0) { ($total - $downloaded) / $instSpeed } else { -1 }
                    $right = ('{0}/{1}  {2}/s  ETA {3}' -f (Format-Size $downloaded), (Format-Size $total), (Format-Size $instSpeed), (Format-Time $eta))
                    Draw-ProgressBar -Fraction $frac -Right $right
                }
            }

            $fs.Close(); $stream.Close(); $resp.Close()
            Draw-ProgressBar -Fraction 1.0 -Right ('{0}/{1}  done' -f (Format-Size $downloaded), (Format-Size $total))
            Write-Host ''
            return
        }
        catch {
            try { if ($fs) { $fs.Close() } } catch { }
            try { if ($stream) { $stream.Close() } } catch { }
            try { if ($resp) { $resp.Close() } } catch { }

            if ($attempt -ge $MaxAttempts) {
                throw "Download failed after $attempt attempts: $($_.Exception.Message)"
            }
            Write-Host ''
            Warn ("Connection dropped (attempt $attempt). Resuming in 5s...  [$($_.Exception.Message)]")
            Start-Sleep -Seconds 5
        }
    }
}

# ---------------------------------------------------------------
#  Integrity
# ---------------------------------------------------------------

function Test-Integrity {
    param([string]$Path, [string]$ExpectedSha256)

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Warn 'Manifest did not provide a SHA-256 hash; skipping integrity check.'
        return $true
    }
    Step 'Verifying download integrity (SHA-256)...'
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    if ($actual -ieq $ExpectedSha256) {
        Ok "Integrity verified ($($actual.Substring(0,16))...)."
        return $true
    }
    Fail 'Checksum mismatch! The download is corrupt or tampered with.'
    Write-Host ("       expected: $ExpectedSha256") -ForegroundColor DarkGray
    Write-Host ("       actual:   $actual")          -ForegroundColor DarkGray
    return $false
}

# ---------------------------------------------------------------
#  Extraction: tar.exe primary, .NET ZipArchive fallback
# ---------------------------------------------------------------

function Expand-FlutterArchive {
    param([string]$ZipPath, [string]$Destination)

    $spin = '|/-\'.ToCharArray()
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'

    if (Test-Path $tar) {
        Step 'Extracting with tar (handles large archives)...'
        $proc = Start-Process -FilePath $tar -ArgumentList @('-xf', "`"$ZipPath`"", '-C', "`"$Destination`"") -PassThru -NoNewWindow
        $i = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.HasExited) {
            try { [Console]::CursorLeft = 0 } catch { }
            Write-Host ("   $($spin[$i % 4]) unpacking...  elapsed $(Format-Time $sw.Elapsed.TotalSeconds)      ") -NoNewline
            $i++; Start-Sleep -Milliseconds 120
        }
        Write-Host ''
        if ($proc.ExitCode -eq 0) { return $true }
        Warn "tar exited with code $($proc.ExitCode); falling back to .NET extractor."
    }

    # Fallback: per-entry extraction with progress (PS 5.1 compatible)
    Step 'Extracting with .NET ZipArchive...'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $count = $zip.Entries.Count
        $done = 0
        foreach ($entry in $zip.Entries) {
            $target = Join-Path $Destination $entry.FullName
            if ([string]::IsNullOrEmpty($entry.Name)) {
                # directory entry
                $null = New-Item -ItemType Directory -Force -Path $target
            } else {
                $dir = Split-Path $target -Parent
                if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
            $done++
            if (($done % 75) -eq 0 -or $done -eq $count) {
                Draw-ProgressBar -Fraction ($done / $count) -Right "$done/$count files"
            }
        }
        Write-Host ''
        return $true
    }
    finally { $zip.Dispose() }
}

# ---------------------------------------------------------------
#  PATH
# ---------------------------------------------------------------

function Add-ToSystemPath {
    param([string]$Dir)

    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = $current -split ';' | Where-Object { $_ -ne '' }
    if ($parts -contains $Dir) {
        Ok 'Flutter is already on the system PATH.'
        return
    }
    $newPath = ($current.TrimEnd(';') + ';' + $Dir)
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
    # Reflect in the current session too.
    $env:Path = $env:Path.TrimEnd(';') + ';' + $Dir
    Ok "Added $Dir to the system PATH."
}

function Get-InstalledFlutterVersion {
    param([string]$BinDir)
    $exe = Join-Path $BinDir 'flutter.bat'
    if (-not (Test-Path $exe)) { return $null }
    try {
        $out = & $exe --version 2>$null | Select-Object -First 1
        if ($out -match 'Flutter\s+([0-9]+\.[0-9]+\.[0-9]+)') { return $Matches[1] }
    } catch { }
    return 'unknown'
}

# ===============================================================
#  MAIN
# ===============================================================

$script:Vt = Enable-VirtualTerminal
Show-Banner

$installDir = Join-Path $InstallRoot 'flutter'
$binDir     = Join-Path $installDir 'bin'
$zipPath    = Join-Path $env:TEMP 'flutter_sdk_download.zip'

try {
    # 1) Resolve the latest release
    Step "Checking the latest Flutter ($Channel) release..."
    $rel = Get-LatestRelease -Channel $Channel
    Ok "Latest ${Channel}: Flutter $($rel.Version) ($($rel.Arch))"

    # 2) Skip if already current
    $installed = Get-InstalledFlutterVersion -BinDir $binDir
    if ($installed) {
        if ($installed -eq $rel.Version) {
            Ok "Flutter $installed is already installed and up to date."
            Add-ToSystemPath -Dir $binDir
            Write-Host ''
            Write-Center "Nothing to do. You're current!" { param($l) C $l 80 220 120 }
            Write-Host ''
            return
        }
        Warn "Found Flutter $installed; updating to $($rel.Version)..."
        Step 'Removing the previous installation...'
        Remove-Item -Recurse -Force $installDir -ErrorAction SilentlyContinue
    }

    # 3) Download (resumable). If a stale partial from a different version exists, drop it.
    if (Test-Path $zipPath) {
        Step 'Found a previous partial download; attempting to resume it.'
    }
    Step "Downloading Flutter $($rel.Version)..."
    Write-Host ("       $($rel.Url)") -ForegroundColor DarkGray
    Invoke-ResumableDownload -Url $rel.Url -Destination $zipPath

    # 4) Verify integrity (delete + abort on mismatch)
    if (-not (Test-Integrity -Path $zipPath -ExpectedSha256 $rel.Sha256)) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        throw 'Integrity check failed. The corrupt file was deleted; please re-run the installer.'
    }

    # 5) Extract
    if (-not (Test-Path $installDir)) { $null = New-Item -ItemType Directory -Force -Path $installDir | Out-Null }
    if (-not (Expand-FlutterArchive -ZipPath $zipPath -Destination $InstallRoot)) {
        throw 'Extraction failed.'
    }
    if (-not (Test-Path (Join-Path $binDir 'flutter.bat'))) {
        throw "Extraction completed but flutter.bat was not found in $binDir."
    }
    Ok "Extracted to $installDir"

    # 6) Cleanup the zip
    Step 'Cleaning up the downloaded archive...'
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # 7) PATH
    Add-ToSystemPath -Dir $binDir

    # 8) Confirm
    Step 'Confirming the installation...'
    $finalVersion = Get-InstalledFlutterVersion -BinDir $binDir
    Ok "Flutter $finalVersion is ready."

    Write-Host ''
    Write-Center '====================  SUCCESS  ====================' { param($l) C $l 80 220 120 }
    Write-Host ''
    Write-Host (C '  Next steps:' 120 200 255)
    Write-Host '    1) Open a NEW terminal (so the PATH refreshes).'
    Write-Host '    2) Run:  ' -NoNewline; Write-Host (C 'flutter doctor' 120 200 255)
    Write-Host '    3) In your project, run:  ' -NoNewline; Write-Host (C 'flutter pub get' 120 200 255)
    Write-Host ''
}
catch {
    Write-Host ''
    Fail $_.Exception.Message
    Write-Host ''
    Write-Host '  The installer can be re-run safely; downloads resume where they left off.' -ForegroundColor DarkGray
    exit 1
}
