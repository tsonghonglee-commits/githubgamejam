[CmdletBinding()]
param(
    [ValidateSet('Editor', 'Run', 'Check', 'ExportWindows', 'ExportWeb')]
    [string]$Task = 'Editor'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localConfigPath = Join-Path $projectRoot '.local/godot.psd1'
$engine = $env:GODOT4

if (-not $engine -and (Test-Path -LiteralPath $localConfigPath)) {
    $engine = (Import-PowerShellDataFile -LiteralPath $localConfigPath).Executable
}
if (-not $engine) {
    foreach ($candidate in @('godot4', 'godot')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { $engine = $command.Source; break }
    }
}
if (-not $engine -or -not (Test-Path -LiteralPath $engine)) {
    throw 'Godot not found. Set GODOT4 or .local/godot.psd1; see README.md.'
}

$versionOutput = @(& $engine --headless --version 2>&1)
if ($LASTEXITCODE -ne 0 -or ($versionOutput -join '') -notmatch '^4\.7\.2\.stable\.') {
    throw ('Godot 4.7.2 stable is required. Found: ' + ($versionOutput -join ' '))
}

function Invoke-GodotChecked {
    param([string[]]$EngineArguments)
    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $engine @EngineArguments 2>&1)
        $engineExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorPreference
    }
    $lines = @($output | ForEach-Object { $_.ToString() })
    $lines | ForEach-Object { Write-Host $_ }
    if ($engineExitCode -ne 0 -or ($lines -match '(SCRIPT ERROR:|ERROR:)')) {
        throw ('Godot task failed (exit code ' + $engineExitCode + ').')
    }
}

switch ($Task) {
    'Editor' {
        Start-Process -FilePath $engine -ArgumentList @('--path', ('"' + $projectRoot + '"'), '--editor') -WindowStyle Hidden
    }
    'Run' {
        & $engine --path $projectRoot
        if ($LASTEXITCODE -ne 0) { throw 'Game process failed.' }
    }
    'Check' {
        Invoke-GodotChecked -EngineArguments @('--headless', '--path', $projectRoot, '--editor', '--quit')
        Invoke-GodotChecked -EngineArguments @('--headless', '--path', $projectRoot, '--quit-after', '3')
        Write-Host 'Project import and startup checks passed.'
    }
    'ExportWindows' {
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'builds/windows') -Force | Out-Null
        Invoke-GodotChecked -EngineArguments @('--headless', '--path', $projectRoot, '--export-release', 'Windows Desktop')
    }
    'ExportWeb' {
        New-Item -ItemType Directory -Path (Join-Path $projectRoot 'builds/web') -Force | Out-Null
        Invoke-GodotChecked -EngineArguments @('--headless', '--path', $projectRoot, '--export-release', 'Web')
    }
}
