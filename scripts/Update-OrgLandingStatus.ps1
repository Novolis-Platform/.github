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
$workspaceRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$cliProject = Join-Path $workspaceRoot 'novolis-tools\src\Novolis.Tools.Docs.Cli\Novolis.Tools.Docs.Cli.csproj'

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
)

if ($ProfileReadme) {
    $argsList += @('--readme', (Resolve-Path $ProfileReadme).Path)
}

& dotnet @argsList
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
