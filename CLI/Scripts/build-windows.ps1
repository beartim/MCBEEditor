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
& cmake -S $native -B $nativeBuild -A x64 "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" "-DMCBE_BUILD_CLI_TEST_TOOLS=$testTools"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed: $LASTEXITCODE" }
& cmake --build $nativeBuild --config Release --target MCBEEditor.LevelDB.Native
if ($LASTEXITCODE -ne 0) { throw "Native LevelDB build failed: $LASTEXITCODE" }

& dotnet build $project --configuration Release
if ($LASTEXITCODE -ne 0) { throw "CLI build failed: $LASTEXITCODE" }
$binary = Join-Path $root 'CLI\Windows\bin\Release\net10.0\mcbe-cli.exe'
$nativeCopy = Join-Path (Split-Path -Parent $binary) 'MCBEEditor.LevelDB.Native.dll'
if (-not (Test-Path $binary) -or -not (Test-Path $nativeCopy)) { throw 'CLI executable or native DLL is missing from the output.' }

if ($Test) {
    & cmake --build $nativeBuild --config Release --target mcbe_cli_create_test_db
    if ($LASTEXITCODE -ne 0) { throw 'Native database fixture tool build failed.' }
    $fixtureTool = Join-Path $root 'CLI\build\native-tests\mcbe_cli_create_test_db.exe'
    if (-not (Test-Path -LiteralPath $fixtureTool -PathType Leaf)) { throw 'Native database fixture tool is missing.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\source_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI source audit failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\build_audit.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI build contract audit failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\smoke.py') --backend windows -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI process/parser checks failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\test_smoke_support.py')
    if ($LASTEXITCODE -ne 0) { throw 'CLI test diagnostic encoding checks failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\session_smoke.py') --fixture-tool $fixtureTool -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI session/file lifecycle checks failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\environment_smoke.py') --fixture-tool $fixtureTool -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI level.dat environment/batch checks failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\nbt_conversion_smoke.py') -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI NBT conversion matrix failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\mcbe_snbt_smoke.py') --backend cli -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI MCBE-SNBT roundtrip and invalid-input checks failed.' }
    & python -X utf8 (Join-Path $root 'CLI\Tests\structure_file_smoke.py') -- $binary
    if ($LASTEXITCODE -ne 0) { throw 'CLI structure file preflight failed.' }
    & dotnet run --project (Join-Path $root 'Windows\MCBEEditor.Core.SelfTest\MCBEEditor.Core.SelfTest.csproj') --configuration Release -- --cli-regression
    if ($LASTEXITCODE -ne 0) { throw 'Existing CLI-related core regressions failed.' }
    & dotnet run --project (Join-Path $root 'CLI\Windows.Tests\MCBEEditor.Cli.Tests.csproj') --configuration Release -- $fixtureTool
    if ($LASTEXITCODE -ne 0) { throw 'CLI native world integration tests failed.' }
}

Write-Host "CLI build ready: $binary"
Write-Host 'This is the development/test build. Run build-windows-release.ps1 for the final portable single EXE.'
