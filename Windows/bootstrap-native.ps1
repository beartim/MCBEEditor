$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$vendor = Join-Path $root 'Native\vendor'
$leveldb = Join-Path $vendor 'leveldb-mcpe'
$zlib = Join-Path $vendor 'zlib'
$leveldbTag = '0.8.0a8'
$zlibTag = 'v1.3.1'

New-Item -ItemType Directory -Force -Path $vendor | Out-Null

function Get-GitHubSource([string]$Repo, [string]$Tag, [string]$Destination) {
    $readyMarker = Join-Path $Destination '.mcbe-source-ready'
    if (Test-Path $readyMarker) { return }

    if (Test-Path $Destination) {
        Remove-Item -Recurse -Force $Destination
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        Write-Host "Fetching $Repo ($Tag) with git..."
        & git clone --depth 1 --branch $Tag "https://github.com/$Repo.git" $Destination
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed for $Repo"
        }
    }
    else {
        Write-Host "git was not found. Fetching the GitHub source archive for $Repo ($Tag)..."
        $temp = Join-Path $env:TEMP ('mcbe-native-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            $zip = Join-Path $temp 'source.zip'
            $tagEscaped = [uri]::EscapeDataString($Tag)
            $url = "https://github.com/$Repo/archive/refs/tags/$tagEscaped.zip"
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip

            $expanded = Join-Path $temp 'expanded'
            Expand-Archive -Path $zip -DestinationPath $expanded
            $source = Get-ChildItem -Path $expanded -Directory | Select-Object -First 1
            if (-not $source) {
                throw "Unable to locate extracted source directory for $Repo"
            }
            Move-Item -Path $source.FullName -Destination $Destination
        }
        finally {
            if (Test-Path $temp) {
                Remove-Item -Recurse -Force $temp
            }
        }
    }

    New-Item -ItemType File -Force -Path (Join-Path $Destination '.mcbe-source-ready') | Out-Null
}

Get-GitHubSource 'Amulet-Team/leveldb-mcpe' $leveldbTag $leveldb
Get-GitHubSource 'madler/zlib' $zlibTag $zlib

Write-Host "Native dependencies are ready: leveldb-mcpe $leveldbTag / zlib $zlibTag"
