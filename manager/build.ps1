param([string]$Python = '.\.venv\Scripts\python.exe')
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath $PSScriptRoot
try {
    $pythonExecutable = (Resolve-Path -LiteralPath $Python).Path
    $appConfig = Get-Content -LiteralPath 'app.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $payloadManifest = Get-Content -LiteralPath 'payload5/manifest.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $outputDirectory = Join-Path 'dist' $payloadManifest.version
    & $pythonExecutable -m PyInstaller --noconfirm --clean --onefile --windowed --distpath $outputDirectory --name $appConfig.exe_name --add-data 'frontend;frontend' --add-data 'app.json;.' --add-data 'payload5;payload' launch.py
    if ($LASTEXITCODE -ne 0) { throw 'EXE 打包失败。' }
    Get-Item -LiteralPath (Join-Path $outputDirectory ($appConfig.exe_name + '.exe'))
} finally {
    Pop-Location
}
