param(
    [switch]$SkipNative
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root

try {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        throw 'dotnet was not found. Install the .NET 10 SDK and run build.cmd again.'
    }
    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    if (-not $cmake) {
        throw 'CMake was not found. Install the Visual Studio Desktop development with C++ workload.'
    }

    $version = & dotnet --version
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the installed dotnet SDK version.'
    }
    Write-Host "dotnet SDK: $version"

    if (-not $SkipNative) {
        & (Join-Path $root 'build-native.ps1')
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    & dotnet restore (Join-Path $root 'MCBEEditor.Windows.sln')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & dotnet run --project (Join-Path $root 'MCBEEditor.Core.SelfTest\MCBEEditor.Core.SelfTest.csproj') -c Release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & dotnet build (Join-Path $root 'MCBEEditor.Windows.sln') -c Release --no-restore
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $payloadDir = Join-Path $root 'artifacts\payload'
    $launcherBuild = Join-Path $root 'PortableLauncher\build\x64'
    $dist = Join-Path $root 'dist'
    foreach ($path in @($payloadDir, $launcherBuild, $dist)) {
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    Write-Host ''
    Write-Host 'Publishing self-contained single-file managed payload...'
    & dotnet publish (Join-Path $root 'MCBEEditor.Desktop\MCBEEditor.Desktop.csproj') `
        -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:IncludeAllContentForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true `
        -p:PublishTrimmed=false `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        -o $payloadDir
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $payload = Join-Path $payloadDir 'MCBEEditor.exe'
    if (-not (Test-Path $payload)) {
        throw "Single-file payload was not produced: $payload"
    }

    Write-Host 'Building portable single-EXE launcher...'
    & cmake -S (Join-Path $root 'PortableLauncher') -B $launcherBuild -A x64 `
        "-DMCBE_PAYLOAD_PATH=$payload" "-DMCBE_OUTPUT_DIR=$dist"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & cmake --build $launcherBuild --config Release --target MCBEEditor
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $finalExe = Join-Path $dist 'MCBEEditor.exe'
    if (-not (Test-Path $finalExe)) {
        throw "Portable launcher build completed but MCBEEditor.exe was not found: $finalExe"
    }

    # The distribution directory is intentionally exactly one file.
    Get-ChildItem -LiteralPath $dist -Force | Where-Object { $_.FullName -ne $finalExe } | Remove-Item -Recurse -Force
    $files = @(Get-ChildItem -LiteralPath $dist -File)
    if ($files.Count -ne 1 -or $files[0].Name -ne 'MCBEEditor.exe') {
        throw 'Portable distribution validation failed: dist must contain exactly MCBEEditor.exe.'
    }

    Write-Host ''
    Write-Host 'Build completed successfully.'
    Write-Host 'Portable distribution (single file):'
    Write-Host $finalExe
    Write-Host 'At runtime MCBEEditor creates Textures, Commands and a temporary Cache beside this EXE.'
    Write-Host 'Cache is removed automatically after MCBEEditor exits.'
}
finally {
    Pop-Location
}
