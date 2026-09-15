param([switch]$Test)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$baseBuild = Join-Path $root 'CLI\Scripts\build-windows.ps1'
$project = Join-Path $root 'CLI\Windows\MCBEEditor.Cli.csproj'
$payloadDir = Join-Path $root 'CLI\Windows\artifacts\payload'
$launcherBuild = Join-Path $root 'CLI\Windows\PortableLauncher\build\x64'
$dist = Join-Path $root 'CLI\Windows\dist'
$expectedVersion = 'MCBEEditor CLI 1.0.0'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw '.NET 10 SDK is required.' }
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw 'CMake and the Visual Studio C++ workload are required.' }

# Keep the normal build/test path as the release prerequisite so the final wrapper cannot
# silently bypass parser, LevelDB, persistence, and source audits.
if ($Test) { & $baseBuild -Test } else { & $baseBuild }

foreach ($path in @($payloadDir, $launcherBuild, $dist)) {
    if (Test-Path $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

Write-Host 'Publishing self-contained single-file CLI payload...'
& dotnet publish $project `
    -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:IncludeAllContentForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:PublishTrimmed=false `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $payloadDir
if ($LASTEXITCODE -ne 0) { throw "CLI single-file publish failed: $LASTEXITCODE" }

$payload = Join-Path $payloadDir 'mcbe-cli.exe'
$payloadEntries = @(Get-ChildItem -LiteralPath $payloadDir -Force)
if (-not (Test-Path $payload) -or $payloadEntries.Count -ne 1 -or $payloadEntries[0].PSIsContainer -or $payloadEntries[0].Name -ne 'mcbe-cli.exe') {
    throw 'Managed publish must contain exactly one mcbe-cli.exe payload; native/content files must be bundled for self-extraction.'
}

Write-Host 'Embedding the payload in the console-preserving portable launcher...'
& cmake -S (Join-Path $root 'CLI\Windows\PortableLauncher') -B $launcherBuild -A x64 `
    "-DMCBE_PAYLOAD_PATH=$payload" "-DMCBE_OUTPUT_DIR=$dist"
if ($LASTEXITCODE -ne 0) { throw "CLI launcher configure failed: $LASTEXITCODE" }
& cmake --build $launcherBuild --config Release --target mcbe_cli_portable
if ($LASTEXITCODE -ne 0) { throw "CLI launcher build failed: $LASTEXITCODE" }

$finalExe = Join-Path $dist 'mcbe-cli.exe'
$distEntries = @(Get-ChildItem -LiteralPath $dist -Force)
if (-not (Test-Path $finalExe) -or $distEntries.Count -ne 1 -or $distEntries[0].PSIsContainer -or $distEntries[0].Name -ne 'mcbe-cli.exe') {
    throw 'Portable distribution validation failed: dist must contain exactly one mcbe-cli.exe.'
}

# Test the *outer* EXE from an otherwise empty directory. This catches argument forwarding,
# redirected stdio, portable Commands placement, payload extraction and cleanup regressions.
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('mcbe-cli-release-' + [Guid]::NewGuid().ToString('N'))
$probeBin = Join-Path $probeRoot 'bin'
$probeCwd = Join-Path $probeRoot 'cwd'
New-Item -ItemType Directory -Path $probeBin,$probeCwd | Out-Null
try {
    $probeExe = Join-Path $probeBin 'mcbe-cli.exe'
    Copy-Item -LiteralPath $finalExe -Destination $probeExe
    Set-Content -LiteralPath (Join-Path $probeCwd 'relative-command-file.txt') -Value 'weather query' -Encoding utf8NoBOM

    Push-Location $probeCwd
    try {
        $versionOutput = (& $probeExe --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $versionOutput -ne $expectedVersion) {
            throw "Final EXE --version failed or returned an unexpected version: '$versionOutput'"
        }
        $helpOutput = (& $probeExe --help | Out-String)
        if ($LASTEXITCODE -ne 0 -or $helpOutput -notmatch 'mcbe-cli --interactive') {
            throw 'Final EXE --help startup check failed.'
        }
        $checkOutput = (& $probeExe --check 'weather query' | Out-String)
        if ($LASTEXITCODE -ne 0 -or $checkOutput -notmatch '语法预检通过') {
            throw 'Final EXE --check startup check failed.'
        }
        $relativeOutput = (& $probeExe --check-file 'relative-command-file.txt' | Out-String)
        if ($LASTEXITCODE -ne 0 -or $relativeOutput -notmatch '1 条命令') {
            throw 'Final EXE changed the caller current directory; relative CLI paths are broken.'
        }
        if ($versionOutput.Contains([char]27) -or $helpOutput.Contains([char]27) -or $checkOutput.Contains([char]27) -or $relativeOutput.Contains([char]27)) {
            throw 'Redirected final EXE output contains ANSI escape sequences.'
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path (Join-Path $probeBin 'Commands\ReadMe.txt'))) {
        throw 'Final EXE did not place Commands/ReadMe.txt beside the outer executable.'
    }
    if (Test-Path (Join-Path $probeBin 'Commands\Command.txt')) {
        throw 'Final EXE unexpectedly created Commands/Command.txt.'
    }
    if (Test-Path (Join-Path $probeCwd 'Commands')) {
        throw 'Final EXE incorrectly placed Commands in the caller current directory.'
    }
    $runtimeRoot = Join-Path $probeBin 'Cache\Runtime'
    if (Test-Path $runtimeRoot) {
        $runtimeEntries = @(Get-ChildItem -LiteralPath $runtimeRoot -Force)
        if ($runtimeEntries.Count -ne 0) { throw 'Portable launcher left a payload extraction directory behind.' }
    }
}
finally {
    Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# Reassert the shipping directory after all probes: runtime-created directories were isolated in probeRoot.
$distEntries = @(Get-ChildItem -LiteralPath $dist -Force)
if ($distEntries.Count -ne 1 -or $distEntries[0].PSIsContainer -or $distEntries[0].Name -ne 'mcbe-cli.exe') {
    throw 'Portable distribution no longer contains exactly one file after validation.'
}

Write-Host "Windows CLI portable release ready: $finalExe"
