$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$scoopManifest = Join-Path $env:GITHUB_WORKSPACE $env:SCOOP_MANIFEST
$chocolateyNuspec = Join-Path $env:GITHUB_WORKSPACE $env:CHOCOLATEY_NUSPEC

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Invoke-RestMethod https://get.scoop.sh | Invoke-Expression
$scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
$env:PATH = "$scoopShims;$env:PATH"

scoop install $scoopManifest
if ($LASTEXITCODE -ne 0) { throw 'Scoop install failed.' }
& "$PSScriptRoot/test-installed-command.ps1" `
  -Executable (Get-Command $commandName).Source `
  -CommandName $commandName `
  -Version $version
New-Item -ItemType Directory -Force artifacts/chocolatey | Out-Null
choco pack $chocolateyNuspec --output-directory artifacts/chocolatey
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey pack failed.' }
choco install $commandName --source artifacts/chocolatey --version $version --yes --no-progress
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey install failed.' }
refreshenv
if (-not $?) { throw 'Chocolatey environment refresh failed after install.' }
$chocolateyShim = Join-Path $env:ChocolateyInstall "bin\$commandName.exe"
if (-not (Test-Path $chocolateyShim)) { throw 'Chocolatey shim was not found.' }
& $chocolateyShim version
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey shim version check failed.' }
$packageRoot = Join-Path $env:ChocolateyInstall "lib\$commandName"
$installedExecutable = Get-ChildItem $packageRoot -Filter "$commandName.exe" -Recurse |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $installedExecutable) { throw 'Chocolatey installed executable was not found.' }
& "$PSScriptRoot/test-installed-command.ps1" `
  -Executable $installedExecutable `
  -CommandName $commandName `
  -Version $version
