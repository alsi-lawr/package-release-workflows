param(
  [Parameter(Mandatory = $true)]
  [string] $Executable,

  [Parameter(Mandatory = $true)]
  [string] $CommandName,

  [Parameter(Mandatory = $true)]
  [string] $Version
)

$ErrorActionPreference = 'Stop'

$versionOutput = (& $Executable version 2>&1) -join "`n"
$versionExitCode = $LASTEXITCODE
if ($versionExitCode -ne 0) {
  throw "$CommandName version check failed with exit code $versionExitCode`: $versionOutput"
}
$expectedVersion = "$CommandName $Version"
if ($versionOutput.Trim() -ne $expectedVersion) {
  throw "Unexpected version output: '$($versionOutput.Trim())'; expected '$expectedVersion'."
}

$helpOutput = (& $Executable help 2>&1) -join "`n"
$helpExitCode = $LASTEXITCODE
if ($helpExitCode -ne 0) {
  throw "$CommandName help check failed with exit code $helpExitCode`: $helpOutput"
}
foreach ($marker in @('Usage:', 'Required Twitch configuration', 'Server Owner Guide')) {
  if (-not $helpOutput.Contains($marker)) { throw "Help output is missing '$marker'." }
}
