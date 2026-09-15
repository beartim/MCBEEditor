param([switch]$Test)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$native = Join-Path $root 'Windows\Native'
$nativeBuild = Join-Path $native 'build\x64'
$project = Join-Path $root 'CLI\Windows\MCBEEditor.Cli.csproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw '.NET 10 SDK is required.' }
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw 'CMake and the Visual Studio C++ workload are required.' }
if ($Test -and -not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'Python 3.10 or newer is required for tests.' }

& (Join-Path $root 'Windows\bootstrap-native.ps1')
$testTools = if ($Test) { 'ON' } else { 'OFF' }
& cmake -S $native -B $nativeBuild -A x64 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "-DMCBE_BUILD_CLI_TEST_TOOLS=$testTools"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }
& cmake --build $nativeBuild --config Release --target MCBEEditor.LevelDB.Native
if ($LASTEXITCODE -ne 0) { throw "Native LevelDB build failed: $LASTEXITCODE" }

& dotnet build $project --configuration Release
if ($LASTEXITCODE -ne 0) { throw "CLI build failed: $LASTEXITCODE" }
$binary = Join-Path $root 'CLI\Windows\bin\Release\net10.0\mcbe-cli.exe'
$nativeCopy = Join-Path (Split-Path -Parent $binary) 'MCBEEditor.LevelDB.Native.dll'
if (-not (Test-Path $binary) -or -not (Test-Path $nativeCopy)) { throw 'CLI executable or native DLL is missing from the output.' }

if ($Test) {
    & python (Join-Path $root 'CLI\Tests\source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage02_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 02 source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage03_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 03 source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage04_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 04 source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage04c_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 04c source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage04d_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 04d source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage04e_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 04e source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage05a_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 05a source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage05b_source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 05b source audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage05c_final_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 05c final audit failed.' }
    & python (Join-Path $root 'CLI\Tests\stage06_conversion_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI stage 06 conversion audit failed.' }
    & python (Join-Path $root 'CLI\Tests\smoke.py') --backend windows -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI process/parser checks failed.' }
    & dotnet run --project (Join-Path $root 'Windows\MCBEEditor.Core.SelfTest\MCBEEditor.Core.SelfTest.csproj') --configuration Release -- --cli-regression
    if ($LASTEXITCODE -ne 0) { throw 'Existing CLI-related core regressions failed.' }
    & cmake --build $nativeBuild --config Release --target mcbe_cli_create_test_db
    if ($LASTEXITCODE -ne 0) { throw 'Native database fixture tool build failed.' }
    $fixtureTool = Join-Path $root 'CLI\build\native-tests\mcbe_cli_create_test_db.exe'
    & dotnet run --project (Join-Path $root 'CLI\Windows.Tests\MCBEEditor.Cli.Tests.csproj') --configuration Release -- $fixtureTool
    if ($LASTEXITCODE -ne 0) { throw 'CLI native world integration tests failed.' }
}

Write-Host "CLI build ready: $binary"
Write-Host 'This is the development/test build. Run build-windows-release.ps1 for the final portable single EXE.'
