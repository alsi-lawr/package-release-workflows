$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$executableName = if ($env:WINDOWS_EXECUTABLE_NAME) { $env:WINDOWS_EXECUTABLE_NAME } else { "$commandName.exe" }
$scope = if ($env:WINGET_SCOPE) { $env:WINGET_SCOPE } else { 'machine' }
$smokeScript = Join-Path $env:GITHUB_WORKSPACE "$($env:SMOKE_SCRIPT).ps1"
$manifestDirectory = Join-Path $env:GITHUB_WORKSPACE ($env:WINGET_MANIFEST_PREFIX + '/' + $version)

$installerManifest = @(Get-ChildItem $manifestDirectory -Filter '*.installer.yaml')
if ($installerManifest.Count -ne 1) { throw 'Expected exactly one WinGet installer manifest.' }
$manifestLines = @(Get-Content $installerManifest[0].FullName)
$installerType = @($manifestLines | ForEach-Object { if ($_ -match '^InstallerType:\s*(\S+)') { $Matches[1] } })
if ($installerType.Count -ne 1) { throw 'Expected one WinGet installer type.' }
if ($installerType[0] -eq 'zip' -and -not ($manifestLines -contains '    ArchiveBinariesDependOnPath: true')) {
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
winget install --manifest $manifestDirectory --scope $scope --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw 'WinGet install failed.' }
if ($env:WINGET_UNINSTALL_KEY) {
  $registration = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$env:WINGET_UNINSTALL_KEY"
  $installedExecutable = Join-Path $registration.InstallLocation $executableName
} else {
  $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
  $machinePath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine)
  $packagePaths = @(@($machinePath, $userPath) -split ';' | Where-Object {
    $_ -like '*\WinGet\Packages\*' -and (Test-Path (Join-Path $_ $executableName))
  })
  if ($packagePaths.Count -ne 1) { throw 'WinGet did not add exactly one installed package directory to PATH.' }
  $installedExecutable = Join-Path $packagePaths[0] $executableName
}
if (-not (Test-Path $installedExecutable)) { throw 'WinGet installed executable was not found.' }
& $smokeScript $installedExecutable -Version $version
if (-not $?) { throw 'WinGet installed-product smoke failed.' }
