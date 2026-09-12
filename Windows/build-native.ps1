$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$native = Join-Path $root 'Native'
$build = Join-Path $native 'build\x64'

$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if (-not $cmake) {
    throw 'CMake was not found. Install the Visual Studio Desktop development with C++ workload, including CMake and MSVC.'
}

& (Join-Path $root 'bootstrap-native.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force -Path $build | Out-Null
Write-Host 'Configuring MCBEEditor LevelDB native x64...'
& cmake -S $native -B $build -A x64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Building MCBEEditor.LevelDB.Native.dll...'
& cmake --build $build --config Release --target MCBEEditor.LevelDB.Native
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$dll = Join-Path $native 'bin\x64\MCBEEditor.LevelDB.Native.dll'
if (-not (Test-Path $dll)) {
    throw "Native build completed but the DLL was not found: $dll"
}
Write-Host "Native LevelDB build completed: $dll"
