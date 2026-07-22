$ErrorActionPreference = 'Stop'

$version = $env:VERSION
$commandName = $env:COMMAND_NAME
$stateDirectory = Join-Path $env:LOCALAPPDATA $env:STATE_DIR_NAME
$manifestDirectory = Join-Path $env:GITHUB_WORKSPACE ($env:WINGET_MANIFEST_PREFIX + '/' + $version)

$installerManifest = @(Get-ChildItem $manifestDirectory -Filter '*.installer.yaml')
if ($installerManifest.Count -ne 1) { throw 'Expected exactly one WinGet installer manifest.' }
$manifestLines = @(Get-Content $installerManifest[0].FullName)
if (-not ($manifestLines -contains '    ArchiveBinariesDependOnPath: true')) {
  if ($version -ne '0.1.2') { throw 'WinGet archive manifest must enable ArchiveBinariesDependOnPath.' }
  $updatedLines = foreach ($line in $manifestLines) {
    $line
    if ($line -eq '    NestedInstallerType: portable') {
      '    ArchiveBinariesDependOnPath: true'
    }
  }
  Set-Content $installerManifest[0].FullName $updatedLines
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

New-Item -ItemType Directory -Force $stateDirectory | Out-Null
Set-Content (Join-Path $stateDirectory 'marker') 'preserve'
winget validate --manifest $manifestDirectory
if ($LASTEXITCODE -ne 0) { throw 'WinGet manifest validation failed.' }
winget settings --enable LocalManifestFiles
if ($LASTEXITCODE -ne 0) { throw 'WinGet could not enable local manifest files.' }
winget install --manifest $manifestDirectory --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw 'WinGet install failed.' }
$userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
$env:PATH = "$userPath;$env:PATH"
& "$PSScriptRoot/test-installed-command.ps1" `
  -Executable (Get-Command $commandName).Source `
  -CommandName $commandName `
  -Version $version
winget uninstall --id $env:WINGET_IDENTIFIER --exact --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw 'WinGet uninstall failed.' }
if (Get-Command $commandName -ErrorAction SilentlyContinue) { throw 'WinGet left the command installed.' }
if ((Get-Content (Join-Path $stateDirectory 'marker')) -ne 'preserve') { throw 'WinGet uninstall changed user data.' }
