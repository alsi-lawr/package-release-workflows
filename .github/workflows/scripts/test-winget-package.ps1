$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$smokeScript = Join-Path $env:GITHUB_WORKSPACE $env:SMOKE_SCRIPT
$manifestDirectory = Join-Path $env:GITHUB_WORKSPACE ($env:WINGET_MANIFEST_PREFIX + '/' + $version)
$python = (Get-Command python -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

$installerManifest = @(Get-ChildItem $manifestDirectory -Filter '*.installer.yaml')
if ($installerManifest.Count -ne 1) { throw 'Expected exactly one WinGet installer manifest.' }
$manifestLines = @(Get-Content $installerManifest[0].FullName)
if (-not ($manifestLines -contains '    ArchiveBinariesDependOnPath: true')) {
  throw 'WinGet archive manifest must enable ArchiveBinariesDependOnPath.'
}

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

winget validate --manifest $manifestDirectory
if ($LASTEXITCODE -ne 0) { throw 'WinGet manifest validation failed.' }
winget settings --enable LocalManifestFiles
if ($LASTEXITCODE -ne 0) { throw 'WinGet could not enable local manifest files.' }
winget install --manifest $manifestDirectory --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw 'WinGet install failed.' }
$userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
$machinePath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine)
$packagePaths = @(@($machinePath, $userPath) -split ';' | Where-Object {
  $_ -like '*\WinGet\Packages\*' -and (Test-Path (Join-Path $_ "$commandName.exe"))
})
if ($packagePaths.Count -ne 1) { throw 'WinGet did not add exactly one installed package directory to PATH.' }
$installedExecutable = Join-Path $packagePaths[0] "$commandName.exe"
& $python $smokeScript $installedExecutable --version $version
if ($LASTEXITCODE -ne 0) { throw 'WinGet installed-product smoke failed.' }
