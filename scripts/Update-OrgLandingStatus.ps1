#Requires -Version 7.0
<#
.SYNOPSIS
  Regenerates the org-landing CI status and package-version matrices in profile/README.md.

.DESCRIPTION
  Queries GitHub for Novolis-Platform repositories, latest workflow conclusions, and NuGet
  packages. Emits shields.io badges (green when success / version known). Replaces the block
  between <!-- novolis-org-status:start --> and <!-- novolis-org-status:end -->.

.PARAMETER Org
  GitHub organization login. Default: Novolis-Platform.

.PARAMETER ProfileReadme
  Path to profile/README.md. Defaults to ../profile/README.md relative to this script.

.PARAMETER ThrottleLimit
  Max parallel gh/API calls. Default: 16.

.EXAMPLE
  pwsh -File scripts/Update-OrgLandingStatus.ps1
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

function Find-Workflow {
    param([string[]] $Files, [string[]] $Candidates)
    foreach ($c in $Candidates) {
        if ($Files -contains $c) { return $c }
    }
    return $null
}

function Encode-ShieldPath {
    param([string] $Text)
    # shields.io path encoding: - _ space → -- __ _
    return (($Text -replace '-', '--') -replace '_', '__') -replace ' ', '_'
}

function Get-StatusShield {
    param(
        [string] $Repo,
        [string] $WorkflowFile,
        [string] $Label,
        [string] $Conclusion
    )
    if (-not $WorkflowFile) { return '—' }
    $href = "https://github.com/$Org/$Repo/actions/workflows/$WorkflowFile"
    $color = switch ($Conclusion) {
        'success' { 'brightgreen' }
        'failure' { 'red' }
        'cancelled' { 'lightgrey' }
        'skipped' { 'lightgrey' }
        'timed_out' { 'red' }
        'action_required' { 'yellow' }
        'neutral' { 'yellow' }
        'startup_failure' { 'red' }
        default { 'lightgrey' }
    }
    $message = if ($Conclusion) { $Conclusion } else { 'none' }
    $shieldLabel = Encode-ShieldPath $Label
    $shieldMessage = Encode-ShieldPath $message
    $url = "https://img.shields.io/badge/${shieldLabel}-${shieldMessage}-${color}"
    return "[![$Label $message]($url)]($href)"
}

function Get-VersionShield {
    param(
        [string] $Version,
        [string] $Href,
        [string] $Label = 'GPR'
    )
    if ([string]::IsNullOrWhiteSpace($Version)) { return '—' }
    $shieldLabel = Encode-ShieldPath $Label
    $shieldMessage = Encode-ShieldPath $Version
    $url = "https://img.shields.io/badge/${shieldLabel}-${shieldMessage}-brightgreen"
    return "[![$Label $Version]($url)]($Href)"
}

function Get-LatestWorkflowConclusion {
    param(
        [string] $Repo,
        [string] $WorkflowFile
    )
    if (-not $WorkflowFile) { return $null }
    try {
        # Prefer default-branch runs for merge; any recent completed run for others.
        $q = if ($WorkflowFile -eq 'merge.yml') {
            "repos/$Org/$Repo/actions/workflows/$WorkflowFile/runs?per_page=5&branch=main&status=completed"
        }
        else {
            "repos/$Org/$Repo/actions/workflows/$WorkflowFile/runs?per_page=5&status=completed"
        }
        $raw = & gh api $q -q '.[0].conclusion // .workflow_runs[0].conclusion // empty' 2>$null
        if ($LASTEXITCODE -ne 0) {
            # list endpoint returns { workflow_runs: [...] }
            $json = Invoke-GhJson @('api', $q)
            if ($json.workflow_runs -and $json.workflow_runs.Count -gt 0) {
                return [string]$json.workflow_runs[0].conclusion
            }
            return $null
        }
        $text = "$raw".Trim()
        if ($text) { return $text }
        $json = Invoke-GhJson @('api', $q)
        if ($json.workflow_runs -and $json.workflow_runs.Count -gt 0) {
            return [string]$json.workflow_runs[0].conclusion
        }
    }
    catch { }
    return $null
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
    catch { }
    $repoWorkflows[$name] = $files
}

# Build repo → workflow file map for status queries
$repoJobs = [System.Collections.Generic.List[object]]::new()
foreach ($r in ($repos | Sort-Object name)) {
    $name = [string]$r.name
    $files = @($repoWorkflows[$name])
    $pr = Find-Workflow -Files $files -Candidates @('pull-request.yml', 'pull_request.yml', 'ci.yml')
    $merge = Find-Workflow -Files $files -Candidates @('merge.yml')
    $release = Find-Workflow -Files $files -Candidates @('release.yml')
    $repoJobs.Add([pscustomobject]@{
            Name    = $name
            Pr      = $pr
            Merge   = $merge
            Release = $release
        })
}

Write-Host "Resolving workflow conclusions (throttle=$ThrottleLimit)..."
$statusMap = [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()
$repoJobs | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $orgName = $using:Org
    $map = $using:statusMap
    $job = $_
    foreach ($pair in @(
            @{ Key = "$($job.Name)|pr"; File = $job.Pr; PreferMain = $false }
            @{ Key = "$($job.Name)|merge"; File = $job.Merge; PreferMain = $true }
            @{ Key = "$($job.Name)|release"; File = $job.Release; PreferMain = $false }
        )) {
        if (-not $pair.File) {
            [void]$map.TryAdd($pair.Key, '')
            continue
        }
        $conclusion = ''
        try {
            $qs = if ($pair.PreferMain) {
                "per_page=5&branch=main&status=completed"
            }
            else {
                "per_page=5&status=completed"
            }
            $json = & gh api "repos/$orgName/$($job.Name)/actions/workflows/$($pair.File)/runs?$qs" 2>$null | ConvertFrom-Json
            if ($json.workflow_runs -and $json.workflow_runs.Count -gt 0) {
                $conclusion = [string]$json.workflow_runs[0].conclusion
            }
        }
        catch { }
        [void]$map.TryAdd($pair.Key, $conclusion)
    }
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
$successMerges = ($repoJobs | Where-Object {
        $statusMap.ContainsKey("$($_.Name)|merge") -and $statusMap["$($_.Name)|merge"] -eq 'success'
    }).Count

# Group packages by repository name
$packagesByRepo = @{}
$orphanPackages = [System.Collections.Generic.List[object]]::new()
foreach ($p in $packages) {
    $repoName = if ($p.repository -and $p.repository.name) { [string]$p.repository.name } else { '' }
    if (-not $repoName) {
        $orphanPackages.Add($p)
        continue
    }
    if (-not $packagesByRepo.ContainsKey($repoName)) {
        $packagesByRepo[$repoName] = [System.Collections.Generic.List[object]]::new()
    }
    $packagesByRepo[$repoName].Add($p)
}

function Format-PackageCell {
    param([AllowNull()][object] $Pkgs)
    $list = @($Pkgs | Where-Object { $null -ne $_ })
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($p in ($list | Sort-Object name)) {
        $pkgName = [string]$p.name
        $gprVer = if ($versionMap.ContainsKey($pkgName)) { $versionMap[$pkgName] } else { '' }
        $pkgUrl = if ($p.html_url) { [string]$p.html_url } else { "https://github.com/orgs/$Org/packages/nuget/package/$pkgName" }
        $shield = Get-VersionShield -Version $gprVer -Href $pkgUrl -Label 'GPR'
        $nugetVer = if ($nugetOrgMap.ContainsKey($pkgName)) { $nugetOrgMap[$pkgName] } else { '' }
        $nugetPart = if ($nugetVer) {
            ' ' + (Get-VersionShield -Version $nugetVer -Href "https://www.nuget.org/packages/$pkgName" -Label 'nuget.org')
        } else { '' }
        $lines.Add("``$pkgName`` $shield$nugetPart")
    }
    if ($lines.Count -eq 0) { return '—' }
    # GitHub table cells need <br> for multi-line (pipe rows stay one physical line).
    return ($lines -join '<br>')
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine($startMarker)
[void]$sb.AppendLine()
[void]$sb.AppendLine("<!-- Generated by scripts/Update-OrgLandingStatus.ps1 — do not hand-edit. Last run: $generatedAt -->")
[void]$sb.AppendLine()
[void]$sb.AppendLine('### Repos, CI & packages')
[void]$sb.AppendLine()
[void]$sb.AppendLine("One row per repo. Merge successes: **$successMerges** / $($repoJobs.Count). Packages: **$($packages.Count)** on [GitHub Packages](https://github.com/orgs/$Org/packages) · [novolis-registry](https://github.com/$Org/novolis-registry).")
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Repository | PR | Merge | Release | Packages |')
[void]$sb.AppendLine('|------------|----|-------|---------|----------|')

foreach ($job in $repoJobs) {
    $name = $job.Name
    $repoLink = "[``$name``](https://github.com/$Org/$name)"
    $prConc = if ($statusMap.ContainsKey("$name|pr")) { $statusMap["$name|pr"] } else { '' }
    $mergeConc = if ($statusMap.ContainsKey("$name|merge")) { $statusMap["$name|merge"] } else { '' }
    $releaseConc = if ($statusMap.ContainsKey("$name|release")) { $statusMap["$name|release"] } else { '' }

    $prBadge = if ($job.Pr -and $prConc -eq 'success') {
        Get-StatusShield -Repo $name -WorkflowFile $job.Pr -Label 'PR' -Conclusion $prConc
    } else { '—' }
    $mergeBadge = if ($job.Merge -and $mergeConc) {
        Get-StatusShield -Repo $name -WorkflowFile $job.Merge -Label 'merge' -Conclusion $mergeConc
    } else { '—' }
    $releaseBadge = if ($job.Release -and $releaseConc -eq 'success') {
        Get-StatusShield -Repo $name -WorkflowFile $job.Release -Label 'release' -Conclusion $releaseConc
    } else { '—' }

    $pkgs = if ($packagesByRepo.ContainsKey($name)) { @($packagesByRepo[$name]) } else { @() }
    $pkgCell = Format-PackageCell -Pkgs $pkgs

    [void]$sb.AppendLine("| $repoLink | $prBadge | $mergeBadge | $releaseBadge | $pkgCell |")
}

if ($orphanPackages.Count -gt 0) {
    $pkgCell = Format-PackageCell -Pkgs $orphanPackages
    [void]$sb.AppendLine("| *(unlinked packages)* | — | — | — | $pkgCell |")
}

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
Write-Host "  repos=$($repos.Count) packages=$($packages.Count) merge_success=$successMerges"
