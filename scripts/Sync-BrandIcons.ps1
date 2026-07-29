#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Copies the Novolis iconographic mark into every sibling novolis-* repo (and .github brand roots).

.DESCRIPTION
  Source of truth: brand/generated/logo-icon.{svg,png,ico} derived from logo-brand-transparent.svg
  (vector-mark only — no wordmark/tagline).

  Writes per-repo:
    icon.png  — NuGet PackageIcon
    icon.ico  — Windows ApplicationIcon
    brand/logo-icon.svg — optional SVG copy when -IncludeSvg

.PARAMETER WorkspaceRoot
  Parent of .github and novolis-* checkouts. Default: parent of this .github repo.

.PARAMETER IncludeSvg
  Also copy logo-icon.svg next to icon.png as brand/logo-icon.svg (or repo-root logo-icon.svg for templates).
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = '',
    [switch]$IncludeSvg,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$githubRoot = Split-Path -Parent $scriptDir
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Split-Path -Parent $githubRoot
}

$brandGenerated = Join-Path $githubRoot 'brand\generated'
$srcPng = Join-Path $brandGenerated 'logo-icon.png'
$srcIco = Join-Path $brandGenerated 'logo-icon.ico'
$srcSvg = Join-Path $brandGenerated 'logo-icon.svg'

foreach ($p in @($srcPng, $srcSvg)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Missing brand asset: $p — run from brand/: dotnet run generate-pixel-outlines.cs -- icon && png"
    }
}

# Ensure ICO exists as real binary (never use PowerShell `>` redirect — it UTF-16-corrupts ICO).
if (-not (Test-Path -LiteralPath $srcIco)) {
    Write-Host "Generating logo-icon.ico via png-to-ico..."
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'novolis-png-to-ico'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Push-Location $tmp
    try {
        if (-not (Test-Path 'package.json')) { npm init -y | Out-Null }
        if (-not (Test-Path 'node_modules\png-to-ico')) { npm install png-to-ico@2 --silent | Out-Null }
        $pngEsc = $srcPng.Replace('\', '/')
        $icoEsc = $srcIco.Replace('\', '/')
        node -e "const pngToIco=require('png-to-ico');const fs=require('fs');pngToIco('$pngEsc').then(b=>{fs.writeFileSync('$icoEsc',b);console.log('wrote',b.length);});"
    }
    finally {
        Pop-Location
    }
}
if (-not (Test-Path -LiteralPath $srcIco)) {
    throw "Missing brand asset: $srcIco"
}

# Promote stable paths under brand/ (not only generated/)
$brandRoot = Join-Path $githubRoot 'brand'
$promote = @(
    @{ Src = $srcSvg; Dst = Join-Path $brandRoot 'favicon.svg' }
    @{ Src = $srcSvg; Dst = Join-Path $brandRoot 'logo-icon.svg' }
    @{ Src = $srcPng; Dst = Join-Path $brandRoot 'logo-icon.png' }
    @{ Src = $srcIco; Dst = Join-Path $brandRoot 'logo-icon.ico' }
)

function Copy-BrandFile([string]$Src, [string]$Dst) {
    $dir = Split-Path -Parent $Dst
    if (-not (Test-Path -LiteralPath $dir)) {
        if ($WhatIf) { Write-Host "WhatIf: mkdir $dir"; return }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if ($WhatIf) {
        Write-Host "WhatIf: copy $Src -> $Dst"
        return
    }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

foreach ($item in $promote) {
    Copy-BrandFile $item.Src $item.Dst
}

$repos = Get-ChildItem -LiteralPath $WorkspaceRoot -Directory -Filter 'novolis-*' |
    Where-Object { $_.Name -notin @('novolis-governance') -or $true } |
    Sort-Object Name

# Always sync governance too (props live there; icon optional for docs)
$extra = @(
    (Join-Path $WorkspaceRoot 'novolis-governance')
)

$targets = @($repos.FullName) + $extra | Select-Object -Unique

$copied = 0
foreach ($repo in $targets) {
    if (-not (Test-Path -LiteralPath $repo)) { continue }

    Copy-BrandFile $srcPng (Join-Path $repo 'icon.png')
    Copy-BrandFile $srcIco (Join-Path $repo 'icon.ico')
    $copied++

    if ($IncludeSvg) {
        Copy-BrandFile $srcSvg (Join-Path $repo 'logo-icon.svg')
    }

    # Template package + content scaffolds that already reference icon.png
    $templateIconDirs = @(
        (Join-Path $repo 'src\Novolis.Templates')
        (Join-Path $repo 'src\Novolis.Templates\content\Novolis.Templates.GitHubSolution')
        (Join-Path $repo 'src\Novolis.Templates\content\Novolis.Templates.Microservice')
        (Join-Path $repo 'src\Novolis.Templates\content\Novolis.Templates.MonoGame')
        (Join-Path $repo 'src\Novolis.Templates\content\Novolis.Templates.NoXaml.Avalonia.Solution')
    )
    foreach ($dir in $templateIconDirs) {
        if (Test-Path -LiteralPath $dir) {
            Copy-BrandFile $srcPng (Join-Path $dir 'icon.png')
            Copy-BrandFile $srcIco (Join-Path $dir 'icon.ico')
        }
    }
}

Write-Host "Synced brand icon mark into $copied repos under $WorkspaceRoot"
Write-Host "Source: $srcPng"
