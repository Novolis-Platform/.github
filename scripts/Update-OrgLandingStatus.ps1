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

$markupSrc = Join-Path $repoRoot 'novolis-markup\src'
$markdownProj = Join-Path $markupSrc 'Novolis.Markup.Markdown\Novolis.Markup.Markdown.csproj'
$renderingProj = Join-Path $markupSrc 'Novolis.Markup.Markdown.Rendering\Novolis.Markup.Markdown.Rendering.csproj'
if ($cliProject.StartsWith($repoRoot) -and (Test-Path -LiteralPath $markdownProj) -and (Test-Path -LiteralPath $renderingProj)) {
    $toolsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $cliProject))
    $markdownInclude = ($markdownProj -replace '\\', '/')
    $renderingInclude = ($renderingProj -replace '\\', '/')
    Write-Host "Wiring novolis-docs to Markup source at $markupSrc"
    @"
<Project>
  <ItemGroup Condition="`$(MSBuildProjectName) == 'Novolis.Tools.Docs' or `$(MSBuildProjectName) == 'Novolis.Tools.Docs.Cli'">
    <PackageReference Remove="Novolis.Markup.Markdown" />
    <PackageReference Remove="Novolis.Markup.Markdown.Rendering" />
    <ProjectReference Include="$markdownInclude" />
    <ProjectReference Include="$renderingInclude" />
  </ItemGroup>
</Project>
"@ | Set-Content -Path (Join-Path $toolsRoot 'Directory.Build.targets') -Encoding utf8
}

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
