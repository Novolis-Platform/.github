#Requires -Version 7.0
<#
.SYNOPSIS
  Sparse-checkouts docs/ from every public org repository into a corpus folder.

.DESCRIPTION
  Produces {OutDir}/{repo}/docs/**/*.md for novolis-docs site. Uses git
  partial clone + sparse-checkout so only the docs tree is materialized.
#>
param(
    [string] $Org = 'Novolis-Platform',
    [string] $OutDir = '',
    [string] $Token = '',
    [int] $Throttle = 6
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $repoRoot 'corpus'
}

$outPath = [System.IO.Path]::GetFullPath($OutDir)
if (-not $outPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutDir must stay inside $repoRoot (got $outPath)"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required for sparse checkout'
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'gh is required to list organization repositories'
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $Token = $env:GH_TOKEN
    if ([string]::IsNullOrWhiteSpace($Token)) { $Token = $env:GITHUB_TOKEN }
}

Write-Host "Listing public repositories for $Org..."
$repos = @(gh repo list $Org --visibility public --no-archived --limit 200 --json name,defaultBranchRef | ConvertFrom-Json | Sort-Object name)
if ($repos.Count -eq 0) {
    throw "No public repositories found for $Org"
}

if (Test-Path $outPath) {
    Remove-Item -LiteralPath $outPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outPath | Out-Null

$work = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$errors = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

$repos | ForEach-Object -ThrottleLimit $Throttle -Parallel {
    $repo = $_
    $name = [string]$repo.name
    $branch = if ($repo.defaultBranchRef -and $repo.defaultBranchRef.name) { [string]$repo.defaultBranchRef.name } else { 'main' }
    $dest = Join-Path $using:outPath $name
    $org = $using:Org
    $token = $using:Token
    $workBag = $using:work
    $errorBag = $using:errors

    $url = if ([string]::IsNullOrWhiteSpace($token)) {
        "https://github.com/$org/$name.git"
    }
    else {
        "https://x-access-token:${token}@github.com/$org/$name.git"
    }

    try {
        & git clone --filter=blob:none --sparse --depth 1 --branch $branch --quiet $url $dest 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed for $name"
        }

        Push-Location $dest
        try {
            & git sparse-checkout set docs 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "sparse-checkout set docs failed for $name"
            }
        }
        finally {
            Pop-Location
        }

        $docsPath = Join-Path $dest 'docs'
        if (-not (Test-Path $docsPath -PathType Container)) {
            Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            return
        }

        $mdCount = @(Get-ChildItem -Path $docsPath -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue).Count
        if ($mdCount -eq 0) {
            Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            return
        }

        Remove-Item -LiteralPath (Join-Path $dest '.git') -Recurse -Force -ErrorAction SilentlyContinue
        [void]$workBag.Add("$name ($mdCount md)")
    }
    catch {
        [void]$errorBag.Add("${name}: $($_.Exception.Message)")
        if (Test-Path $dest) {
            Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Sparse corpus ready at $outPath"
Write-Host "  repos_with_docs=$($work.Count)"
foreach ($line in ($work | Sort-Object)) {
    Write-Host "  + $line"
}
if ($errors.Count -gt 0) {
    Write-Warning "Skipped/failed $($errors.Count) repositories:"
    foreach ($line in ($errors | Sort-Object)) {
        Write-Warning "  - $line"
    }
}

if ($work.Count -eq 0) {
    throw 'No repository docs/ trees were collected'
}
