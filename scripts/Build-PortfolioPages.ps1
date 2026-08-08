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

# Prefer sibling / workspace Markup source — GPR package Parse is still a stub while markup CI is red.
$markupRoot = $null
foreach ($candidate in @(
        (Join-Path $repoRoot 'novolis-markup\src'),
        (Join-Path (Split-Path $repoRoot -Parent) 'novolis-markup\src')
    )) {
    if ((Test-Path (Join-Path $candidate 'Novolis.Markup.Markdown\Novolis.Markup.Markdown.csproj')) -and
        (Test-Path (Join-Path $candidate 'Novolis.Markup.Markdown.Rendering\Novolis.Markup.Markdown.Rendering.csproj'))) {
        $markupRoot = (Resolve-Path $candidate).Path
        break
    }
}

$pagesTargets = $null
if ($cli.Kind -eq 'project' -and $markupRoot) {
    $toolsRoot = Split-Path (Split-Path (Split-Path $cli.Path -Parent) -Parent) -Parent
    $pagesTargets = Join-Path $toolsRoot 'Directory.Build.targets'
    # MSBuild on Linux wants forward slashes in Include paths.
    $mdProj = ((Join-Path $markupRoot 'Novolis.Markup.Markdown\Novolis.Markup.Markdown.csproj') -replace '\\', '/')
    $renderProj = ((Join-Path $markupRoot 'Novolis.Markup.Markdown.Rendering\Novolis.Markup.Markdown.Rendering.csproj') -replace '\\', '/')
    Write-Host "Wiring novolis-docs to Markup source at $markupRoot"
    @"
<Project>
  <ItemGroup Condition="`$(MSBuildProjectName) == 'Novolis.Tools.Docs' or `$(MSBuildProjectName) == 'Novolis.Tools.Docs.Cli'">
    <PackageReference Remove="Novolis.Markup.Markdown" />
    <PackageReference Remove="Novolis.Markup.Markdown.Rendering" />
    <ProjectReference Include="$mdProj" />
    <ProjectReference Include="$renderProj" />
  </ItemGroup>
</Project>
"@ | Set-Content -Path $pagesTargets -Encoding utf8
}

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

try {
    switch ($cli.Kind) {
        'project' {
            & dotnet run --project $cli.Path -c Release -- @siteArgs
        }
        default {
            & $cli.Path @siteArgs
        }
    }
}
finally {
    if ($pagesTargets -and (Test-Path -LiteralPath $pagesTargets)) {
        Remove-Item -LiteralPath $pagesTargets -Force -ErrorAction SilentlyContinue
    }
}
if ($LASTEXITCODE -ne 0) {
    throw 'novolis-docs site failed'
}

Write-Host "Built $outputPath"
