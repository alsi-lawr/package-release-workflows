$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$stateDirectory = Join-Path $env:LOCALAPPDATA $env:STATE_DIR_NAME
$smokeScript = Join-Path $env:GITHUB_WORKSPACE $env:SMOKE_SCRIPT
$manifestDirectory = Join-Path $env:GITHUB_WORKSPACE ($env:WINGET_MANIFEST_PREFIX + '/' + $version)
$python = (Get-Command python -ErrorAction Stop).Source

$client = Get-Command winget -ErrorAction SilentlyContinue
if ($null -eq $client) {
  Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery
  Repair-WinGetPackageManager -AllUsers -Force -Latest
  $windowsApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
  $env:PATH = "$windowsApps;$env:PATH"
  $client = Get-Command winget -ErrorAction SilentlyContinue
}
if ($null -eq $client) { throw 'WinGet is not available on this runner.' }
& $client.Source --version
if ($LASTEXITCODE -ne 0) { throw 'WinGet is unusable on this runner.' }

New-Item -ItemType Directory -Force $stateDirectory | Out-Null
Set-Content (Join-Path $stateDirectory 'marker') 'preserve'
winget validate --manifest $manifestDirectory
if ($LASTEXITCODE -ne 0) { throw 'WinGet manifest validation failed.' }
winget settings --enable LocalManifestFiles
if ($LASTEXITCODE -ne 0) { throw 'WinGet could not enable local manifest files.' }
winget install --manifest $manifestDirectory --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw 'WinGet install failed.' }
$links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
$env:PATH = "$links;$env:PATH"
& $python $smokeScript (Get-Command $commandName).Source --version $version
if ($LASTEXITCODE -ne 0) { throw 'WinGet smoke test failed.' }
winget uninstall --id $env:WINGET_IDENTIFIER --exact --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw 'WinGet uninstall failed.' }
if (Get-Command $commandName -ErrorAction SilentlyContinue) { throw 'WinGet left the command installed.' }
if ((Get-Content (Join-Path $stateDirectory 'marker')) -ne 'preserve') { throw 'WinGet uninstall changed user data.' }
