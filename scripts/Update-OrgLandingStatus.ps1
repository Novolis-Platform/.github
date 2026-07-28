#Requires -Version 7.0
<#
.SYNOPSIS
  Regenerates the org-landing CI status and package-version matrices in profile/README.md.

.DESCRIPTION
  Queries GitHub for Novolis-Platform repositories, workflow files, and NuGet packages
  (GitHub Packages + nuget.org latest when published). Replaces the block between
  <!-- novolis-org-status:start --> and <!-- novolis-org-status:end -->.

.PARAMETER Org
  GitHub organization login. Default: Novolis-Platform.

.PARAMETER ProfileReadme
  Path to profile/README.md. Defaults to ../profile/README.md relative to this script.

.PARAMETER ThrottleLimit
  Max parallel gh/API calls when resolving package versions. Default: 16.

.EXAMPLE
  pwsh -File .github/scripts/Update-OrgLandingStatus.ps1
#>
param(
    [string] $Org = 'Novolis-Platform',
    [string] $ProfileReadme = '',
    [int] $ThrottleLimit = 16
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'gh CLI is required (authenticated to the org).'
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProfileReadme)) {
    $ProfileReadme = Join-Path $scriptDir '..\profile\README.md'
}
$ProfileReadme = (Resolve-Path $ProfileReadme).Path

$startMarker = '<!-- novolis-org-status:start -->'
$endMarker = '<!-- novolis-org-status:end -->'

function Invoke-GhJson {
    param([Parameter(Mandatory)][string[]] $GhArgs)
    $raw = & gh @GhArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($GhArgs -join ' ') failed: $raw"
    }
    if ([string]::IsNullOrWhiteSpace("$raw")) { return $null }
    return "$raw" | ConvertFrom-Json
}

Write-Host "Listing repositories for $Org..."
$repos = [System.Collections.Generic.List[object]]::new()
$page = 1
while ($true) {
    $batch = Invoke-GhJson @(
        'api'
        "orgs/$Org/repos?per_page=100&page=$page&type=public"
    )
    if ($null -eq $batch -or $batch.Count -eq 0) { break }
    foreach ($r in $batch) {
        if ($r.archived) { continue }
        $repos.Add($r)
    }
    if ($batch.Count -lt 100) { break }
    $page++
}

Write-Host "  $($repos.Count) public non-archived repos"

Write-Host 'Discovering workflows...'
$repoWorkflows = @{}
foreach ($r in ($repos | Sort-Object name)) {
    $name = [string]$r.name
    $files = @()
    try {
        $contents = Invoke-GhJson @(
            'api'
            "repos/$Org/$name/contents/.github/workflows"
        )
        if ($contents) {
            foreach ($c in @($contents)) {
                if ($c.name -match '\.ya?ml$') { $files += [string]$c.name }
            }
        }
    }
    catch {
        # Missing workflows directory is fine.
    }
    $repoWorkflows[$name] = $files
}

function Get-WorkflowBadge {
    param(
        [string] $Repo,
        [string] $WorkflowFile,
        [string] $Label
    )
    if (-not $WorkflowFile) { return '—' }
    $url = "https://github.com/$Org/$Repo/actions/workflows/$WorkflowFile/badge.svg"
    $href = "https://github.com/$Org/$Repo/actions/workflows/$WorkflowFile"
    return "[![$Label]($url)]($href)"
}

function Find-Workflow {
    param([string[]] $Files, [string[]] $Candidates)
    foreach ($c in $Candidates) {
        if ($Files -contains $c) { return $c }
    }
    return $null
}

Write-Host "Listing NuGet packages on GitHub Packages..."
$packages = [System.Collections.Generic.List[object]]::new()
$page = 1
while ($true) {
    $batch = Invoke-GhJson @(
        'api'
        "orgs/$Org/packages?package_type=nuget&per_page=100&page=$page"
    )
    if ($null -eq $batch -or $batch.Count -eq 0) { break }
    foreach ($p in $batch) { $packages.Add($p) }
    if ($batch.Count -lt 100) { break }
    $page++
}
Write-Host "  $($packages.Count) packages"

Write-Host "Resolving latest versions (throttle=$ThrottleLimit)..."
$versionMap = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()
$nugetOrgMap = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()

$packages | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $pkgName = [string]$_.name
    $orgName = $using:Org
    $vMap = $using:versionMap
    $nMap = $using:nugetOrgMap

    $latest = ''
    try {
        $raw = & gh api "orgs/$orgName/packages/nuget/$pkgName/versions?per_page=1" -q '.[0].name' 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) { $latest = "$raw".Trim() }
    }
    catch { }
    [void]$vMap.TryAdd($pkgName, $latest)

    $nugetLatest = ''
    try {
        $id = $pkgName.ToLowerInvariant()
        $idx = Invoke-RestMethod -Uri "https://api.nuget.org/v3-flatcontainer/$id/index.json" -TimeoutSec 20
        if ($idx.versions -and $idx.versions.Count -gt 0) {
            $nugetLatest = [string]$idx.versions[-1]
        }
    }
    catch { }
    [void]$nMap.TryAdd($pkgName, $nugetLatest)
}

$generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine($startMarker)
[void]$sb.AppendLine()
[void]$sb.AppendLine("<!-- Generated by scripts/Update-OrgLandingStatus.ps1 — do not hand-edit. Last run: $generatedAt -->")
[void]$sb.AppendLine()
[void]$sb.AppendLine('### Repository CI')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Repository | PR | Merge / package | Release |')
[void]$sb.AppendLine('|------------|----|-----------------|---------|')

foreach ($r in ($repos | Sort-Object name)) {
    $name = [string]$r.name
    $files = @($repoWorkflows[$name])
    # Only consumer workflow names — never reusable definitions like
    # dotnet-merge-publish.yml (those live in novolis-workflows).
    $pr = Find-Workflow -Files $files -Candidates @('pull-request.yml', 'pull_request.yml', 'ci.yml')
    $merge = Find-Workflow -Files $files -Candidates @('merge.yml')
    $release = Find-Workflow -Files $files -Candidates @('release.yml')

    $repoLink = "[``$name``](https://github.com/$Org/$name)"
    $prBadge = Get-WorkflowBadge -Repo $name -WorkflowFile $pr -Label 'PR'
    $mergeBadge = Get-WorkflowBadge -Repo $name -WorkflowFile $merge -Label 'Merge'
    $releaseBadge = Get-WorkflowBadge -Repo $name -WorkflowFile $release -Label 'Release'
    [void]$sb.AppendLine("| $repoLink | $prBadge | $mergeBadge | $releaseBadge |")
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('### Package versions')
[void]$sb.AppendLine()
[void]$sb.AppendLine("Latest **GitHub Packages** versions (and **nuget.org** when published). Feed: ``https://nuget.pkg.github.com/$Org/index.json``. Full catalog: [org packages](https://github.com/orgs/$Org/packages) · [novolis-registry](https://github.com/$Org/novolis-registry).")
[void]$sb.AppendLine()
[void]$sb.AppendLine('<details>')
[void]$sb.AppendLine("<summary>All NuGet packages ($($packages.Count))</summary>")
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Package | Repository | GitHub Packages | nuget.org |')
[void]$sb.AppendLine('|---------|------------|-----------------|-----------|')

foreach ($p in ($packages | Sort-Object name)) {
    $pkgName = [string]$p.name
    $repoName = if ($p.repository -and $p.repository.name) { [string]$p.repository.name } else { '' }
    $repoCell = if ($repoName) { "[``$repoName``](https://github.com/$Org/$repoName)" } else { '—' }
    $gprVer = if ($versionMap.ContainsKey($pkgName) -and $versionMap[$pkgName]) { $versionMap[$pkgName] } else { '—' }
    $pkgUrl = if ($p.html_url) { [string]$p.html_url } else { "https://github.com/orgs/$Org/packages/nuget/package/$pkgName" }
    $gprCell = if ($gprVer -ne '—') { "[``$gprVer``]($pkgUrl)" } else { '—' }

    $nugetVer = if ($nugetOrgMap.ContainsKey($pkgName)) { $nugetOrgMap[$pkgName] } else { '' }
    if ($nugetVer) {
        $badge = "https://img.shields.io/nuget/v/$pkgName?label=nuget.org"
        $nugetCell = "[![$pkgName]($badge)](https://www.nuget.org/packages/$pkgName)"
    }
    else {
        $nugetCell = '—'
    }

    [void]$sb.AppendLine("| ``$pkgName`` | $repoCell | $gprCell | $nugetCell |")
}

[void]$sb.AppendLine()
[void]$sb.AppendLine('</details>')
[void]$sb.AppendLine()
[void]$sb.AppendLine($endMarker)

$block = $sb.ToString().TrimEnd() + [Environment]::NewLine

$body = Get-Content -Path $ProfileReadme -Raw
if ($body -notmatch [regex]::Escape($startMarker)) {
    throw "Missing $startMarker in $ProfileReadme — add the markers before running this script."
}
if ($body -notmatch [regex]::Escape($endMarker)) {
    throw "Missing $endMarker in $ProfileReadme."
}

$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker)
$updated = [regex]::Replace($body, $pattern, { param($m) $block.TrimEnd() })
if (-not $updated.EndsWith("`n")) { $updated += "`n" }

Set-Content -Path $ProfileReadme -Value $updated -Encoding utf8NoBOM
Write-Host "Updated $ProfileReadme"
Write-Host "  repos=$($repos.Count) packages=$($packages.Count)"
