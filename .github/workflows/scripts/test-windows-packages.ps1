$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$stateDirectory = Join-Path $env:LOCALAPPDATA $env:STATE_DIR_NAME
$scoopManifest = Join-Path $env:GITHUB_WORKSPACE $env:SCOOP_MANIFEST
$chocolateyNuspec = Join-Path $env:GITHUB_WORKSPACE $env:CHOCOLATEY_NUSPEC

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Invoke-RestMethod https://get.scoop.sh | Invoke-Expression
$scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
$env:PATH = "$scoopShims;$env:PATH"

New-Item -ItemType Directory -Force $stateDirectory | Out-Null
Set-Content (Join-Path $stateDirectory 'marker') 'preserve'
scoop install $scoopManifest
if ($LASTEXITCODE -ne 0) { throw 'Scoop install failed.' }
& "$PSScriptRoot/test-installed-command.ps1" `
  -Executable (Get-Command $commandName).Source `
  -CommandName $commandName `
  -Version $version
scoop update $commandName
if ($LASTEXITCODE -ne 0) { throw 'Scoop update failed.' }
if ((Get-Content (Join-Path $stateDirectory 'marker')) -ne 'preserve') { throw 'Scoop update changed user data.' }
scoop uninstall $commandName
if ($LASTEXITCODE -ne 0) { throw 'Scoop uninstall failed.' }
if (Get-Command $commandName -ErrorAction SilentlyContinue) { throw 'Scoop left the command installed.' }
if ((Get-Content (Join-Path $stateDirectory 'marker')) -ne 'preserve') { throw 'Scoop uninstall changed user data.' }

Set-Content (Join-Path $stateDirectory 'marker') 'preserve'
New-Item -ItemType Directory -Force artifacts/chocolatey | Out-Null
choco pack $chocolateyNuspec --output-directory artifacts/chocolatey
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey pack failed.' }
choco install $commandName --source artifacts/chocolatey --version $version --yes --no-progress
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey install failed.' }
refreshenv
if (-not $?) { throw 'Chocolatey environment refresh failed after install.' }
$shim = (Get-Command $commandName).Source
& $shim version
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey shim version check failed.' }
$packageRoot = Join-Path $env:ChocolateyInstall "lib\$commandName"
$installedExecutable = Get-ChildItem $packageRoot -Filter "$commandName.exe" -Recurse |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $installedExecutable) { throw 'Chocolatey installed executable was not found.' }
& "$PSScriptRoot/test-installed-command.ps1" `
  -Executable $installedExecutable `
  -CommandName $commandName `
  -Version $version
choco upgrade $commandName --source artifacts/chocolatey --version $version --force --yes --no-progress
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey upgrade failed.' }
if ((Get-Content (Join-Path $stateDirectory 'marker')) -ne 'preserve') { throw 'Chocolatey update changed user data.' }
choco uninstall $commandName --yes --no-progress
if ($LASTEXITCODE -ne 0) { throw 'Chocolatey uninstall failed.' }
refreshenv
if (-not $?) { throw 'Chocolatey environment refresh failed after uninstall.' }
if (Get-Command $commandName -ErrorAction SilentlyContinue) { throw 'Chocolatey left the command installed.' }
if ((Get-Content (Join-Path $stateDirectory 'marker')) -ne 'preserve') { throw 'Chocolatey uninstall changed user data.' }
