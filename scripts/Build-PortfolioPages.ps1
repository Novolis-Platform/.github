#Requires -Version 7.0
<#
.SYNOPSIS
  Builds the Novolis portfolio documentation site for GitHub Pages.

.DESCRIPTION
  1. Sparse-checkouts docs/ from every public org repository into corpus/
  2. Runs novolis-docs site (Novolis.Tools.Docs.Cli) to render HTML via Novolis.Markup
#>
param(
    [string] $Org = 'Novolis-Platform',
    [string] $OutputDir = '',
    [string] $CorpusDir = '',
    [string] $DocsCli = '',
    [string] $ToolVersion = '2026.1.*',
    [switch] $SkipCollect,
    [switch] $SkipToolInstall
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot '_site'
}
if ([string]::IsNullOrWhiteSpace($CorpusDir)) {
    $CorpusDir = Join-Path $repoRoot 'corpus'
}

$outputPath = [System.IO.Path]::GetFullPath($OutputDir)
$corpusPath = [System.IO.Path]::GetFullPath($CorpusDir)
if (-not $outputPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must stay inside $repoRoot"
}
if (-not $corpusPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "CorpusDir must stay inside $repoRoot"
}

function Resolve-NovolisDocsCli {
    param([string] $Explicit, [string] $Version)

    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        $explicitPath = if ([System.IO.Path]::IsPathRooted($Explicit)) { $Explicit } else { Join-Path $repoRoot $Explicit }
        if (Test-Path -LiteralPath $explicitPath) {
            $resolved = (Resolve-Path $explicitPath).Path
            if ($resolved.EndsWith('.csproj', [System.StringComparison]::OrdinalIgnoreCase)) {
                return @{ Kind = 'project'; Path = $resolved }
            }
            return @{ Kind = 'file'; Path = $resolved }
        }
    }

    $workspaceCli = Join-Path $repoRoot 'novolis-tools\src\Novolis.Tools.Docs.Cli\Novolis.Tools.Docs.Cli.csproj'
    if (Test-Path -LiteralPath $workspaceCli) {
        return @{ Kind = 'project'; Path = $workspaceCli }
    }

    $cmd = Get-Command novolis-docs -ErrorAction SilentlyContinue
    if ($cmd) {
        return @{ Kind = 'command'; Path = $cmd.Source }
    }

    $toolDir = Join-Path $repoRoot '.tools'
    $localTool = Join-Path $toolDir $(if ($IsWindows) { 'novolis-docs.exe' } else { 'novolis-docs' })
    if (Test-Path -LiteralPath $localTool) {
        return @{ Kind = 'file'; Path = $localTool }
    }

    $siblingCli = Join-Path (Split-Path $repoRoot -Parent) 'novolis-tools\src\Novolis.Tools.Docs.Cli\Novolis.Tools.Docs.Cli.csproj'
    if (Test-Path -LiteralPath $siblingCli) {
        return @{ Kind = 'project'; Path = $siblingCli }
    }

    if ($SkipToolInstall) {
        throw 'novolis-docs not found. Install Novolis.Tools.Docs.Cli or pass -DocsCli.'
    }

    Write-Host "Installing Novolis.Tools.Docs.Cli $Version into $toolDir ..."
    New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
    Push-Location $repoRoot
    try {
        & dotnet tool install Novolis.Tools.Docs.Cli --tool-path $toolDir --version $Version
        if ($LASTEXITCODE -ne 0) {
            throw 'dotnet tool install Novolis.Tools.Docs.Cli failed'
        }
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $localTool)) {
        throw "novolis-docs was not installed at $localTool"
    }
    return @{ Kind = 'file'; Path = $localTool }
}

if (-not $SkipCollect) {
    Write-Host 'Collecting docs/ via sparse checkout...'
    & (Join-Path $scriptDir 'Collect-OrgDocsSparse.ps1') -Org $Org -OutDir $corpusPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Collect-OrgDocsSparse.ps1 failed'
    }
}
elseif (-not (Test-Path $corpusPath)) {
    throw "SkipCollect was set but corpus is missing: $corpusPath"
}

$cli = Resolve-NovolisDocsCli -Explicit $DocsCli -Version $ToolVersion
$assets = Join-Path $repoRoot 'site\assets'
$brand = Join-Path $repoRoot 'brand'
$baseUrl = "https://$($Org.ToLowerInvariant()).github.io/.github/"

Write-Host "Building docs site with novolis-docs ($($cli.Kind))..."
$siteArgs = @(
    'site',
    '--corpus', $corpusPath,
    '--out', $outputPath,
    '--org', $Org,
    '--assets', $assets,
    '--brand', $brand,
    '--base-url', $baseUrl
)

switch ($cli.Kind) {
    'project' {
        & dotnet run --project $cli.Path -c Release -- @siteArgs
    }
    default {
        & $cli.Path @siteArgs
    }
}
if ($LASTEXITCODE -ne 0) {
    throw 'novolis-docs site failed'
}

Write-Host "Built $outputPath"
