#Requires -Version 7.0
<#
.SYNOPSIS
  Thin shim to novolis-docs org-readme (org profile CI + package tables).
#>
param(
    [string] $Org = 'Novolis-Platform',
    [string] $ProfileReadme = '',
    [int] $ThrottleLimit = 16,
    [int] $MaxPackagesPerRepo = 3
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
$forestCli = Join-Path (Split-Path $repoRoot -Parent) 'novolis-tools\src\Novolis.Tools.Docs.Cli\Novolis.Tools.Docs.Cli.csproj'
$inRepoCli = Join-Path $repoRoot 'novolis-tools\src\Novolis.Tools.Docs.Cli\Novolis.Tools.Docs.Cli.csproj'
if (Test-Path -LiteralPath $forestCli) {
    $cliProject = $forestCli
}
elseif (Test-Path -LiteralPath $inRepoCli) {
    $cliProject = $inRepoCli
}
else {
    throw "novolis-docs project not found at $forestCli or $inRepoCli"
}

$readmePath = if ($ProfileReadme) { (Resolve-Path $ProfileReadme).Path } else { Join-Path $scriptDir '..\profile\README.md' }
$statusJson = Join-Path $scriptDir '..\site\status.json'

$argsList = @(
    'run'
    '--project'
    $cliProject
    '--no-launch-profile'
    '--'
    'org-readme'
    '--org'
    $Org
    '--throttle'
    "$ThrottleLimit"
    '--max-packages'
    "$MaxPackagesPerRepo"
    '--readme'
    $readmePath
    '--status-json'
    $statusJson
)

& dotnet @argsList
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
