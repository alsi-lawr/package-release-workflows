$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$smokeScript = Join-Path $env:GITHUB_WORKSPACE $env:SMOKE_SCRIPT
$scoopManifest = Join-Path $env:GITHUB_WORKSPACE $env:SCOOP_MANIFEST
$chocolateyNuspec = Join-Path $env:GITHUB_WORKSPACE $env:CHOCOLATEY_NUSPEC

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Invoke-RestMethod https://get.scoop.sh | Invoke-Expression
$scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
$env:PATH = "$scoopShims;$env:PATH"

scoop install $scoopManifest
if ($LASTEXITCODE -ne 0) { throw 'Scoop install failed.' }
$scoopExecutable = (Get-Command $commandName).Source
python $smokeScript $scoopExecutable --version $version
if ($LASTEXITCODE -ne 0) { throw 'Scoop installed-product smoke failed.' }

New-Item -ItemType Directory -Force artifacts/chocolatey | Out-Null
choco pack $chocolateyNuspec --output-directory artifacts/chocolatey
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey pack failed.' }
choco install $commandName --source artifacts/chocolatey --version $version --yes --no-progress
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey install failed.' }
refreshenv
if (-not $?) { throw 'Chocolatey environment refresh failed after install.' }
$packageRoot = Join-Path $env:ChocolateyInstall "lib\$commandName"
$installedExecutable = Get-ChildItem $packageRoot -Filter "$commandName.exe" -Recurse |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $installedExecutable) { throw 'Chocolatey installed executable was not found.' }
python $smokeScript $installedExecutable --version $version
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey installed-product smoke failed.' }
