#Requires -Version 7.0
<#
.SYNOPSIS
  Builds the Novolis portfolio documentation site for GitHub Pages.

.DESCRIPTION
  Pulls markdown documentation from every public Novolis-Platform repository
  (root README, docs/, package READMEs under src/, plus .github org corpus),
  renders static HTML, and builds a portfolio index from GitHub repository,
  workflow, and package metadata when gh is available.

  Local sibling checkouts under WorkspaceRoot are preferred; otherwise content
  is fetched from GitHub (tree + raw). No npm/Ruby dependency.
#>
param(
    [string] $Org = 'Novolis-Platform',
    [string] $OutputDir = '',
    [string] $WorkspaceRoot = '',
    [int] $FetchThrottle = 16,
    [switch] $SkipGitHub
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot '_site'
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $repoRoot
}

$outputPath = [System.IO.Path]::GetFullPath($OutputDir)
if (-not $outputPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must stay inside $repoRoot"
}

if (Test-Path $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath | Out-Null
New-Item -ItemType Directory -Path (Join-Path $outputPath 'assets') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $outputPath 'docs') | Out-Null

$generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
$baseUrl = "https://$($Org.ToLowerInvariant()).github.io/.github/"
$maxDocBytes = 500000

function Html {
    param([AllowNull()][object] $Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Slugify {
    param([Parameter(Mandatory)][string] $Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'item' }
    return $slug
}

function Invoke-GhJson {
    param([Parameter(Mandatory)][string[]] $GhArgs)
    $raw = & gh @GhArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh $($GhArgs -join ' ') failed: $raw"
    }
    if ([string]::IsNullOrWhiteSpace("$raw")) { return $null }
    return "$raw" | ConvertFrom-Json
}

function Test-GhReady {
    if ($SkipGitHub) { return $false }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $false }
    $null = & gh auth status 2>$null
    return ($LASTEXITCODE -eq 0 -or -not [string]::IsNullOrWhiteSpace($env:GH_TOKEN))
}

function Get-RepoFallback {
    $names = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($banner in Get-ChildItem -Path (Join-Path $repoRoot 'brand\banners') -Filter '*.svg' -ErrorAction SilentlyContinue) {
        if ($banner.BaseName -like 'novolis-*') { [void]$names.Add($banner.BaseName) }
    }
    foreach ($m in [regex]::Matches((Get-Content -Raw (Join-Path $repoRoot 'profile\README.md')), 'Novolis-Platform/([^)\s]+)')) {
        $name = [string]$m.Groups[1].Value
        if ($name -notmatch '^(packages|package|actions|blob|raw)') {
            [void]$names.Add(($name -split '[/#?]')[0])
        }
    }
    if (Test-Path $WorkspaceRoot -PathType Container) {
        foreach ($dir in Get-ChildItem -Path $WorkspaceRoot -Directory -ErrorAction SilentlyContinue) {
            if ($dir.Name -eq '.github' -or $dir.Name -like 'novolis-*') {
                [void]$names.Add($dir.Name)
            }
        }
    }
    [void]$names.Add('.github')

    foreach ($name in $names) {
        [pscustomobject]@{
            name = $name
            description = ''
            url = "https://github.com/$Org/$name"
            homepageUrl = ''
            primaryLanguage = $null
            repositoryTopics = @()
            pushedAt = ''
            defaultBranchRef = [pscustomobject]@{ name = 'main' }
        }
    }
}

function Get-PortfolioData {
    $ghReady = Test-GhReady
    if ($ghReady) {
        Write-Host "Loading repositories for $Org..."
        $repos = @(Invoke-GhJson @(
            'repo', 'list', $Org,
            '--visibility', 'public',
            '--no-archived',
            '--limit', '200',
            '--json', 'name,description,url,homepageUrl,primaryLanguage,repositoryTopics,pushedAt,defaultBranchRef'
        ) | Sort-Object name)
    }
    else {
        Write-Host 'gh is not available/authenticated; using local repo fallback.'
        $repos = @(Get-RepoFallback | Sort-Object name)
    }

    $workflowMap = @{}
    if ($ghReady) {
        Write-Host 'Discovering workflow files...'
        foreach ($repo in $repos) {
            $name = [string]$repo.name
            $files = @()
            try {
                $contents = Invoke-GhJson @('api', "repos/$Org/$name/contents/.github/workflows")
                foreach ($entry in @($contents)) {
                    if ($entry.name -match '\.ya?ml$') { $files += [string]$entry.name }
                }
            }
            catch { }
            $workflowMap[$name] = @($files | Sort-Object)
        }
    }

    $packageMap = @{}
    if ($ghReady) {
        Write-Host 'Loading package inventory...'
        $page = 1
        while ($true) {
            $batch = @(Invoke-GhJson @('api', "orgs/$Org/packages?package_type=nuget&per_page=100&page=$page"))
            if ($batch.Count -eq 0) { break }
            foreach ($pkg in $batch) {
                $repoName = if ($pkg.repository -and $pkg.repository.name) { [string]$pkg.repository.name } else { '' }
                if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
                if (-not $packageMap.ContainsKey($repoName)) {
                    $packageMap[$repoName] = [System.Collections.Generic.List[object]]::new()
                }
                $packageMap[$repoName].Add($pkg)
            }
            if ($batch.Count -lt 100) { break }
            $page++
        }
    }

    $items = foreach ($repo in $repos) {
        $name = [string]$repo.name
        $topics = @()
        foreach ($topic in @($repo.repositoryTopics)) {
            if ($topic.name) { $topics += [string]$topic.name }
        }
        $language = if ($repo.primaryLanguage -and $repo.primaryLanguage.name) { [string]$repo.primaryLanguage.name } else { 'Docs' }
        $packages = if ($packageMap.ContainsKey($name)) { @($packageMap[$name] | Sort-Object name) } else { @() }
        $workflows = if ($workflowMap.ContainsKey($name)) { @($workflowMap[$name]) } else { @() }
        $branch = if ($repo.defaultBranchRef -and $repo.defaultBranchRef.name) { [string]$repo.defaultBranchRef.name } else { 'main' }
        $kind = if ($name -in @('.github', 'novolis-governance', 'novolis-workflows', 'novolis-registry', 'novolis-template-dotnet', 'novolis-templates', 'novolis-smoketest')) {
            'Platform'
        }
        elseif ($name -in @('novolis-apps', 'novolis-install', 'novolis-tools')) {
            'Apps and Tools'
        }
        elseif ($name -in @('novolis-dogfooding')) {
            'Labs'
        }
        else {
            'Libraries'
        }

        [pscustomobject]@{
            Name = $name
            Description = if ($repo.description) { [string]$repo.description } else { "Novolis repository: $name." }
            Url = if ($repo.url) { [string]$repo.url } else { "https://github.com/$Org/$name" }
            HomepageUrl = if ($repo.homepageUrl) { [string]$repo.homepageUrl } else { '' }
            Language = $language
            Topics = $topics
            PushedAt = if ($repo.pushedAt) { [string]$repo.pushedAt } else { '' }
            Branch = $branch
            Workflows = $workflows
            Packages = $packages
            Kind = $kind
            Banner = if (Test-Path (Join-Path $repoRoot "brand\banners\$name.svg")) { "assets/banners/$name.svg" } else { '' }
        }
    }

    return @($items | Sort-Object Kind, Name)
}

function Convert-InlineMarkdown {
    param([string] $Text)
    $encoded = Html $Text
    $encoded = [regex]::Replace($encoded, '`([^`]+)`', '<code>$1</code>')
    $encoded = [regex]::Replace($encoded, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $encoded = [regex]::Replace($encoded, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
    return $encoded
}

function Convert-MarkdownToHtml {
    param([string] $Markdown)
    $lines = $Markdown -split "`r?`n"
    $sb = [System.Text.StringBuilder]::new()
    $inCode = $false
    $inList = $false
    $inTable = $false

    function Close-Blocks {
        if ($inList) {
            [void]$sb.AppendLine('</ul>')
            Set-Variable -Name inList -Value $false -Scope 1
        }
        if ($inTable) {
            [void]$sb.AppendLine('</tbody></table>')
            Set-Variable -Name inTable -Value $false -Scope 1
        }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*```') {
            if ($inCode) {
                [void]$sb.AppendLine('</code></pre>')
                $inCode = $false
            }
            else {
                Close-Blocks
                [void]$sb.AppendLine('<pre><code>')
                $inCode = $true
            }
            continue
        }
        if ($inCode) {
            [void]$sb.AppendLine((Html $line))
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            Close-Blocks
            continue
        }
        if ($line -match '^\s*---+\s*$') {
            Close-Blocks
            [void]$sb.AppendLine('<hr/>')
            continue
        }
        if ($line -match '^(#{1,6})\s+(.+)$') {
            Close-Blocks
            $level = $Matches[1].Length
            $text = Convert-InlineMarkdown $Matches[2]
            [void]$sb.AppendLine("<h$level>$text</h$level>")
            continue
        }
        if ($line -match '^\s*[-*]\s+(.+)$') {
            if (-not $inList) {
                Close-Blocks
                [void]$sb.AppendLine('<ul>')
                $inList = $true
            }
            [void]$sb.AppendLine('<li>' + (Convert-InlineMarkdown $Matches[1]) + '</li>')
            continue
        }
        if ($line -match '^\s*\|(.+)\|\s*$' -and ($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$') {
            Close-Blocks
            $headers = @($line.Trim('|') -split '\|' | ForEach-Object { Convert-InlineMarkdown $_.Trim() })
            [void]$sb.AppendLine('<table><thead><tr>')
            foreach ($h in $headers) { [void]$sb.AppendLine("<th>$h</th>") }
            [void]$sb.AppendLine('</tr></thead><tbody>')
            $inTable = $true
            $i++
            continue
        }
        if ($inTable -and $line -match '^\s*\|(.+)\|\s*$') {
            $cells = @($line.Trim('|') -split '\|' | ForEach-Object { Convert-InlineMarkdown $_.Trim() })
            [void]$sb.AppendLine('<tr>')
            foreach ($cell in $cells) { [void]$sb.AppendLine("<td>$cell</td>") }
            [void]$sb.AppendLine('</tr>')
            continue
        }
        if ($line -match '^\s*>\s?(.+)$') {
            Close-Blocks
            [void]$sb.AppendLine('<blockquote>' + (Convert-InlineMarkdown $Matches[1]) + '</blockquote>')
            continue
        }

        Close-Blocks
        [void]$sb.AppendLine('<p>' + (Convert-InlineMarkdown $line.Trim()) + '</p>')
    }
    if ($inCode) { [void]$sb.AppendLine('</code></pre>') }
    Close-Blocks
    return $sb.ToString()
}

function New-PageHtml {
    param(
        [string] $Title,
        [string] $Description,
        [string] $Body,
        [string] $ExtraClass = ''
    )
    $safeTitle = Html $Title
    $safeDescription = Html $Description
    return @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="description" content="$safeDescription"/>
  <title>$safeTitle - Novolis Docs</title>
  <link rel="icon" href="../assets/brand/favicon.svg"/>
  <link rel="stylesheet" href="../assets/site.css"/>
</head>
<body class="$ExtraClass">
  <header class="topbar">
    <a class="brand" href="../index.html" aria-label="Novolis docs home">
      <img src="../assets/brand/logo-icon.svg" alt=""/>
      <span>Novolis Docs</span>
    </a>
    <nav>
      <a href="../index.html#portfolio">Portfolio</a>
      <a href="../index.html#docs">Docs</a>
      <a href="https://github.com/$Org">GitHub</a>
    </nav>
  </header>
  <main class="article-shell">
    $Body
  </main>
  <footer class="footer">
    <span>Generated $generatedAt</span>
    <a href="https://github.com/$Org/.github">Source</a>
  </footer>
</body>
</html>
"@
}

function Test-DocPathIncluded {
    param(
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $RepoName
    )
    $p = $RelativePath.Replace('\', '/').TrimStart('/')
    if ($p -match '(^|/)(bin|obj|node_modules|\.git|\.vs|\.cursor|packages)(/|$)') { return $false }
    if ($p -match '(^|/)(_site|artifacts|TestResults)(/|$)') { return $false }
    if ($RepoName -eq 'novolis-experimental' -and $p -match '(^|/)source(/|$)') { return $false }

    if ($RepoName -eq '.github') {
        return $p -match '^(README\.md|profile/|docs/|plans/|brand/README\.md|wiki/)'
    }

    if ($p -eq 'README.md') { return $true }
    if ($p -match '^(CONTRIBUTING|SECURITY|CHANGELOG|AGENTS)\.md$') { return $true }
    if ($p.StartsWith('docs/') -and $p.EndsWith('.md')) { return $true }
    if ($p.StartsWith('wiki/') -and $p.EndsWith('.md')) { return $true }
    if ($p -match '^src/.+/README\.md$') { return $true }
    return $false
}

function Get-DocKind {
    param(
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $RepoName
    )
    $p = $RelativePath.Replace('\', '/')
    if ($RepoName -eq '.github') {
        if ($p.StartsWith('plans/')) { return 'Plans' }
        if ($p.StartsWith('brand/')) { return 'Brand' }
        if ($p.StartsWith('profile/')) { return 'Profile' }
        if ($p.StartsWith('wiki/')) { return 'Wiki' }
        return 'Org'
    }
    if ($p -match '^src/.+/README\.md$') { return 'Package' }
    if ($p.StartsWith('docs/')) { return 'Docs' }
    if ($p.StartsWith('wiki/')) { return 'Wiki' }
    if ($p -eq 'README.md') { return 'README' }
    return 'Docs'
}

function Get-LocalRepoPath {
    param([Parameter(Mandatory)][string] $RepoName)
    if ($RepoName -eq '.github') { return $repoRoot }
    $candidate = Join-Path $WorkspaceRoot $RepoName
    if (-not (Test-Path $candidate -PathType Container)) { return $null }
    if ((Test-Path (Join-Path $candidate '.git')) -or (Test-Path (Join-Path $candidate 'README.md')) -or (Test-Path (Join-Path $candidate 'docs'))) {
        return $candidate
    }
    return $null
}

function Get-LocalDocPaths {
    param(
        [Parameter(Mandatory)][string] $RepoName,
        [Parameter(Mandatory)][string] $LocalRoot
    )
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -Path $LocalRoot -Recurse -Filter '*.md' -File -ErrorAction SilentlyContinue) {
        $relative = [System.IO.Path]::GetRelativePath($LocalRoot, $file.FullName).Replace('\', '/')
        if (-not (Test-DocPathIncluded -RelativePath $relative -RepoName $RepoName)) { continue }
        if ($file.Length -gt $maxDocBytes) { continue }
        $found.Add($relative)
    }
    return @($found | Sort-Object -Unique)
}

function Get-RemoteDocPaths {
    param(
        [Parameter(Mandatory)][string] $RepoName,
        [Parameter(Mandatory)][string] $Branch
    )
    try {
        $tree = Invoke-GhJson @('api', "repos/$Org/$RepoName/git/trees/${Branch}?recursive=1")
    }
    catch {
        try {
            $tree = Invoke-GhJson @('api', "repos/$Org/$RepoName/git/trees/HEAD?recursive=1")
        }
        catch {
            Write-Warning "Tree listing failed for $RepoName : $_"
            return @()
        }
    }

    $paths = foreach ($item in @($tree.tree)) {
        if ($item.type -ne 'blob') { continue }
        $path = [string]$item.path
        if (-not $path.EndsWith('.md')) { continue }
        if (-not (Test-DocPathIncluded -RelativePath $path -RepoName $RepoName)) { continue }
        if ($item.size -and [int]$item.size -gt $maxDocBytes) { continue }
        $path
    }
    return @($paths | Sort-Object -Unique)
}

function Resolve-MarkdownHref {
    param(
        [Parameter(Mandatory)][string] $Href,
        [Parameter(Mandatory)][string] $CurrentRelative,
        [Parameter(Mandatory)][hashtable] $SlugByKey
    )
    if ($Href -match '^(https?:|mailto:|#)') { return $Href }
    $pathPart = ($Href -split '#', 2)[0]
    $fragment = if ($Href -match '#(.+)$') { '#' + $Matches[1] } else { '' }
    if ([string]::IsNullOrWhiteSpace($pathPart)) { return $Href }
    if ($pathPart -notmatch '\.md($|\?)') { return $Href }

    $baseParts = [System.Collections.Generic.List[string]]::new()
    $currentParts = @($CurrentRelative.Replace('\', '/') -split '/' | Where-Object { $_ -ne '' })
    if ($currentParts.Count -gt 1) {
        foreach ($part in $currentParts[0..($currentParts.Count - 2)]) { $baseParts.Add($part) }
    }
    foreach ($part in @($pathPart.Replace('\', '/') -split '/' | Where-Object { $_ -ne '' })) {
        if ($part -eq '.') { continue }
        if ($part -eq '..') {
            if ($baseParts.Count -gt 0) { $baseParts.RemoveAt($baseParts.Count - 1) }
            continue
        }
        $baseParts.Add($part)
    }
    $resolved = ($baseParts -join '/')
    if ($SlugByKey.ContainsKey($resolved)) {
        return "$($SlugByKey[$resolved]).html$fragment"
    }
    if ($SlugByKey.ContainsKey($resolved.ToLowerInvariant())) {
        return "$($SlugByKey[$resolved.ToLowerInvariant()]).html$fragment"
    }
    return $Href
}

function Rewrite-DocLinks {
    param(
        [Parameter(Mandatory)][string] $Markdown,
        [Parameter(Mandatory)][string] $CurrentRelative,
        [Parameter(Mandatory)][hashtable] $SlugByKey
    )
    $pattern = '\[([^\]]+)\]\(([^)]+)\)'
    $sb = [System.Text.StringBuilder]::new()
    $last = 0
    foreach ($match in [regex]::Matches($Markdown, $pattern)) {
        [void]$sb.Append($Markdown.Substring($last, $match.Index - $last))
        $label = $match.Groups[1].Value
        $href = $match.Groups[2].Value
        $newHref = Resolve-MarkdownHref -Href $href -CurrentRelative $CurrentRelative -SlugByKey $SlugByKey
        [void]$sb.Append("[$label]($newHref)")
        $last = $match.Index + $match.Length
    }
    [void]$sb.Append($Markdown.Substring($last))
    return $sb.ToString()
}

function Get-MarkdownDocs {
    param([Parameter(Mandatory)][object[]] $ReposItems)

    $ghReady = Test-GhReady
    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($repo in $ReposItems) {
        $name = [string]$repo.Name
        $branch = if ($repo.Branch) { [string]$repo.Branch } else { 'main' }
        $localRoot = Get-LocalRepoPath -RepoName $name
        $paths = @()
        if ($localRoot) {
            Write-Host "Scanning local docs: $name"
            $paths = @(Get-LocalDocPaths -RepoName $name -LocalRoot $localRoot)
        }
        elseif ($ghReady) {
            Write-Host "Listing remote docs: $name"
            $paths = @(Get-RemoteDocPaths -RepoName $name -Branch $branch)
        }
        else {
            continue
        }

        foreach ($relative in $paths) {
            $candidates.Add([pscustomobject]@{
                Repo = $name
                RelativePath = $relative
                Branch = $branch
                LocalRoot = $localRoot
                Kind = Get-DocKind -RelativePath $relative -RepoName $name
            })
        }
    }

    Write-Host "Fetching $($candidates.Count) markdown files (throttle=$FetchThrottle)..."
    $fetched = @(
        $candidates | ForEach-Object -ThrottleLimit $FetchThrottle -Parallel {
            $item = $_
            $org = $using:Org
            $maxDocBytes = $using:maxDocBytes
            $content = $null
            $localRoot = [string]$item.LocalRoot
            $relative = [string]$item.RelativePath
            $repo = [string]$item.Repo
            $branch = [string]$item.Branch

            if (-not [string]::IsNullOrWhiteSpace($localRoot)) {
                $full = Join-Path $localRoot ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
                if (Test-Path -LiteralPath $full -PathType Leaf) {
                    $content = Get-Content -Raw -LiteralPath $full
                }
            }
            if ($null -eq $content) {
                $rawUrl = "https://raw.githubusercontent.com/$org/$repo/$branch/$($relative.Replace('\', '/'))"
                try {
                    $response = Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 60
                    $content = [string]$response.Content
                }
                catch {
                    $content = $null
                }
            }
            if ($null -eq $content) { return $null }
            if ([System.Text.Encoding]::UTF8.GetByteCount($content) -gt $maxDocBytes) { return $null }

            $title = [System.IO.Path]::GetFileNameWithoutExtension($relative)
            $h1 = [regex]::Match($content, '(?m)^#\s+(.+)$')
            if ($h1.Success) { $title = $h1.Groups[1].Value.Trim() }
            $slug = (& {
                $Value = "$repo/$($relative -replace '\.md$', '')".ToLowerInvariant() -replace '[^a-z0-9]+', '-'
                $Value = $Value.Trim('-')
                if ([string]::IsNullOrWhiteSpace($Value)) { 'item' } else { $Value }
            })

            [pscustomobject]@{
                Repo = $repo
                Title = $title
                RelativePath = $relative
                Slug = $slug
                SourceUrl = "https://github.com/$org/$repo/blob/$branch/$relative"
                Body = $content
                Group = $repo
                Kind = [string]$item.Kind
                Branch = $branch
            }
        } | Where-Object { $null -ne $_ }
    )

    foreach ($doc in $fetched) {
        $map = @{}
        foreach ($other in $fetched) {
            if ($other.Repo -ne $doc.Repo) { continue }
            $map[$other.RelativePath] = $other.Slug
            $map[$other.RelativePath.ToLowerInvariant()] = $other.Slug
        }
        $doc.Body = Rewrite-DocLinks -Markdown $doc.Body -CurrentRelative $doc.RelativePath -SlugByKey $map
    }

    return @($fetched | Sort-Object Group, Kind, RelativePath)
}

function Render-Badge {
    param([string] $RepoName, [string] $WorkflowFile)
    $label = [System.IO.Path]::GetFileNameWithoutExtension($WorkflowFile)
    $src = "https://github.com/$Org/$RepoName/actions/workflows/$WorkflowFile/badge.svg"
    $href = "https://github.com/$Org/$RepoName/actions/workflows/$WorkflowFile"
    return "<a class=""badge-link"" href=""$href""><img src=""$src"" alt=""$(Html "$RepoName $label workflow status")""></a>"
}

function Render-PortfolioCard {
    param(
        [object] $Repo,
        [int] $DocCount = 0
    )
    $badgeNames = @('pull-request.yml', 'pull_request.yml', 'ci.yml', 'merge.yml', 'release.yml', 'pages.yml')
    $badges = foreach ($candidate in $badgeNames) {
        if ($Repo.Workflows -contains $candidate) { Render-Badge -RepoName $Repo.Name -WorkflowFile $candidate }
    }
    if (@($badges).Count -eq 0) { $badges = @('<span class="quiet">No public workflow badge</span>') }

    $packages = @($Repo.Packages | Select-Object -First 5)
    $packageHtml = if ($packages.Count -gt 0) {
        ($packages | ForEach-Object {
            $name = [string]$_.name
            $url = if ($_.html_url) { [string]$_.html_url } else { "https://github.com/orgs/$Org/packages/nuget/package/$name" }
            "<a href=""$url"">$(Html $name)</a>"
        }) -join ''
    }
    else {
        '<span class="quiet">No NuGet package linked</span>'
    }

    $topicHtml = if (@($Repo.Topics).Count -gt 0) {
        (@($Repo.Topics) | Select-Object -First 5 | ForEach-Object { "<span>$(Html $_)</span>" }) -join ''
    }
    else {
        '<span>novolis</span>'
    }

    $banner = if ($Repo.Banner) {
        "<img class=""repo-banner"" src=""$(Html $Repo.Banner)"" alt=""""/>"
    }
    else {
        "<div class=""repo-banner text-banner"">$(Html $Repo.Name)</div>"
    }

    $packagesCount = @($Repo.Packages).Count
    $docsLink = if ($DocCount -gt 0) {
        "<a class=""docs-count"" href=""index.html?repo=$(Html $Repo.Name)#docs"">$DocCount docs</a>"
    }
    else {
        '<span class="quiet">No ingested docs</span>'
    }

    return @"
<article class="repo-card" data-kind="$(Html $Repo.Kind)" data-search="$(Html (($Repo.Name + ' ' + $Repo.Description + ' ' + ($Repo.Topics -join ' ')).ToLowerInvariant()))">
  $banner
  <div class="repo-card-body">
    <div class="repo-meta">
      <span>$(Html $Repo.Kind)</span>
      <span>$(Html $Repo.Language)</span>
      <span>$packagesCount packages</span>
      $docsLink
    </div>
    <h3><a href="$(Html $Repo.Url)">$(Html $Repo.Name)</a></h3>
    <p>$(Html $Repo.Description)</p>
    <div class="topic-row">$topicHtml</div>
    <div class="badge-row">$($badges -join '')</div>
    <div class="package-row">$packageHtml</div>
  </div>
</article>
"@
}

function Render-DocCard {
    param([object] $Doc)
    return @"
<article class="doc-card" data-doc-group="$(Html $Doc.Group)" data-doc-kind="$(Html $Doc.Kind)" data-search="$(Html (($Doc.Title + ' ' + $Doc.Group + ' ' + $Doc.Kind + ' ' + $Doc.RelativePath).ToLowerInvariant()))">
  <div class="doc-card-tags">
    <span>$(Html $Doc.Group)</span>
    <span>$(Html $Doc.Kind)</span>
  </div>
  <h3><a href="docs/$(Html $Doc.Slug).html">$(Html $Doc.Title)</a></h3>
  <p>$(Html "$($Doc.Group)/$($Doc.RelativePath)")</p>
  <a class="source-link" href="$(Html $Doc.SourceUrl)">Source markdown</a>
</article>
"@
}

Copy-Item -Path (Join-Path $repoRoot 'brand\logo-icon.svg') -Destination (Join-Path $outputPath 'assets\brand-logo-icon.svg') -Force
New-Item -ItemType Directory -Path (Join-Path $outputPath 'assets\brand') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $outputPath 'assets\banners') | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'brand\favicon.svg') -Destination (Join-Path $outputPath 'assets\brand\favicon.svg') -Force
Copy-Item -Path (Join-Path $repoRoot 'brand\logo-icon.svg') -Destination (Join-Path $outputPath 'assets\brand\logo-icon.svg') -Force
Copy-Item -Path (Join-Path $repoRoot 'brand\logo-brand-transparent.svg') -Destination (Join-Path $outputPath 'assets\brand\logo-brand-transparent.svg') -Force
Copy-Item -Path (Join-Path $repoRoot 'brand\generated\logo-social.png') -Destination (Join-Path $outputPath 'assets\brand\logo-social.png') -Force
Copy-Item -Path (Join-Path $repoRoot 'brand\banners\*.svg') -Destination (Join-Path $outputPath 'assets\banners') -Force
Copy-Item -Path (Join-Path $repoRoot 'site\assets\site.css') -Destination (Join-Path $outputPath 'assets\site.css') -Force
Copy-Item -Path (Join-Path $repoRoot 'site\assets\site.js') -Destination (Join-Path $outputPath 'assets\site.js') -Force

$repos = @(Get-PortfolioData)
$docs = @(Get-MarkdownDocs -ReposItems $repos)
$docsByRepo = @{}
foreach ($group in ($docs | Group-Object Group)) {
    $docsByRepo[$group.Name] = @($group.Group).Count
}

foreach ($doc in $docs) {
    $article = @"
<article class="article">
  <div class="article-kicker">$(Html $doc.Group) / $(Html $doc.Kind) / $(Html $doc.RelativePath)</div>
  <h1>$(Html $doc.Title)</h1>
  <div class="article-actions">
    <a href="$(Html $doc.SourceUrl)">Open source markdown</a>
    <a href="../index.html?repo=$(Html $doc.Group)#docs">More from $(Html $doc.Group)</a>
    <a href="../index.html#docs">Back to docs index</a>
  </div>
  <div class="markdown-body">
    $(Convert-MarkdownToHtml $doc.Body)
  </div>
</article>
"@
    $html = New-PageHtml -Title $doc.Title -Description "Novolis documentation ($($doc.Group)): $($doc.Title)" -Body $article
    Set-Content -Path (Join-Path $outputPath "docs\$($doc.Slug).html") -Value $html -Encoding utf8NoBOM
}

$repoCards = ($repos | ForEach-Object {
    $count = if ($docsByRepo.ContainsKey($_.Name)) { [int]$docsByRepo[$_.Name] } else { 0 }
    Render-PortfolioCard -Repo $_ -DocCount $count
}) -join "`n"
$docCards = ($docs | ForEach-Object { Render-DocCard $_ }) -join "`n"
$repoCount = $repos.Count
$docCount = $docs.Count
$packageCount = (@($repos | ForEach-Object { $_.Packages }) | Where-Object { $null -ne $_ }).Count
$docRepoCount = @($docsByRepo.Keys).Count

$repoFilterOptions = (
    @('<option value="all">All repositories</option>') +
    @($docsByRepo.Keys | Sort-Object | ForEach-Object {
        "<option value=""$(Html $_)"">$(Html $_) ($($docsByRepo[$_]))</option>"
    })
) -join "`n"

$kindFilterOptions = (
    @('<option value="all">All kinds</option>') +
    @(($docs | Select-Object -ExpandProperty Kind -Unique | Sort-Object) | ForEach-Object {
        "<option value=""$(Html $_)"">$(Html $_)</option>"
    })
) -join "`n"

$indexBody = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="description" content="Novolis portfolio documentation aggregated from every public repository: policies, package READMEs, library guides, apps, and platform docs."/>
  <title>Novolis Portfolio Docs</title>
  <link rel="icon" href="assets/brand/favicon.svg"/>
  <link rel="stylesheet" href="assets/site.css"/>
</head>
<body>
  <header class="topbar">
    <a class="brand" href="index.html" aria-label="Novolis docs home">
      <img src="assets/brand/logo-icon.svg" alt=""/>
      <span>Novolis Docs</span>
    </a>
    <nav>
      <a href="#portfolio">Portfolio</a>
      <a href="#docs">Docs</a>
      <a href="https://github.com/$Org">GitHub</a>
    </nav>
  </header>

  <main>
    <section class="hero">
      <div class="hero-grid" aria-hidden="true"></div>
      <div class="hero-content">
        <img class="hero-logo" src="assets/brand/logo-brand-transparent.svg" alt="Novolis"/>
        <p class="eyebrow">Org-wide documentation uplink</p>
        <h1>Modern .NET for realtime systems, graphics, games, studios, and simulations.</h1>
        <p class="hero-copy">A single GitHub Pages console that ingests README, docs/, and package README markdown from every public Novolis repository, plus live portfolio, workflow, and package metadata.</p>
        <div class="hero-actions">
          <a href="#docs">Browse docs</a>
          <a href="#portfolio">Explore portfolio</a>
          <a href="https://github.com/$Org/.github/actions/workflows/pages.yml"><img src="https://github.com/$Org/.github/actions/workflows/pages.yml/badge.svg" alt="Pages workflow status"></a>
        </div>
      </div>
      <div class="telemetry-panel" aria-label="Portfolio telemetry">
        <div><span>$repoCount</span><strong>repositories</strong></div>
        <div><span>$packageCount</span><strong>NuGet packages</strong></div>
        <div><span>$docCount</span><strong>docs pages</strong></div>
        <div><span>$docRepoCount</span><strong>repos with docs</strong></div>
      </div>
    </section>

    <section class="status-strip" aria-label="Workflow status badges">
      <a href="https://github.com/$Org/.github/actions/workflows/pages.yml"><img src="https://github.com/$Org/.github/actions/workflows/pages.yml/badge.svg" alt="Pages workflow status"></a>
      <a href="https://github.com/$Org/.github/actions/workflows/refresh-org-landing.yml"><img src="https://github.com/$Org/.github/actions/workflows/refresh-org-landing.yml/badge.svg" alt="Org landing refresh workflow status"></a>
      <a href="https://github.com/orgs/$Org/packages"><img src="https://img.shields.io/badge/packages-GitHub%20Packages-0a7ea3?logo=nuget" alt="GitHub Packages"></a>
      <a href="https://github.com/$Org"><img src="https://img.shields.io/badge/org-$Org-15171d" alt="GitHub organization"></a>
    </section>

    <section id="portfolio" class="section">
      <div class="section-heading">
        <p class="eyebrow">Library, app, and infrastructure map</p>
        <h2>Portfolio</h2>
      </div>
      <div class="controls">
        <label class="search-box">
          <span>Search</span>
          <input type="search" id="portfolioSearch" placeholder="raylib, audio, workflows, packages"/>
        </label>
        <div class="segmented" role="tablist" aria-label="Portfolio filters">
          <button class="active" data-kind="all">All</button>
          <button data-kind="Libraries">Libraries</button>
          <button data-kind="Apps and Tools">Apps</button>
          <button data-kind="Platform">Platform</button>
          <button data-kind="Labs">Labs</button>
        </div>
      </div>
      <div class="repo-grid" id="repoGrid">
        $repoCards
      </div>
    </section>

    <section id="docs" class="section docs-section">
      <div class="section-heading">
        <p class="eyebrow">Aggregated from every public repository</p>
        <h2>Docs</h2>
      </div>
      <div class="controls docs-controls">
        <label class="search-box">
          <span>Search</span>
          <input type="search" id="docSearch" placeholder="governance, package README, raylib, nuget"/>
        </label>
        <label class="search-box">
          <span>Repository</span>
          <select id="docRepoFilter">
            $repoFilterOptions
          </select>
        </label>
        <label class="search-box">
          <span>Kind</span>
          <select id="docKindFilter">
            $kindFilterOptions
          </select>
        </label>
      </div>
      <div class="doc-grid" id="docGrid">
        $docCards
      </div>
    </section>
  </main>

  <footer class="footer">
    <span>Generated $generatedAt</span>
    <a href="$baseUrl">$baseUrl</a>
    <a href="https://github.com/$Org/.github">Source</a>
  </footer>
  <script src="assets/site.js"></script>
</body>
</html>
"@

Set-Content -Path (Join-Path $outputPath 'index.html') -Value $indexBody -Encoding utf8NoBOM

$nojekyll = Join-Path $outputPath '.nojekyll'
Set-Content -Path $nojekyll -Value '' -Encoding utf8NoBOM

Write-Host "Built $outputPath"
Write-Host "  repos=$repoCount docs=$docCount docRepos=$docRepoCount packages=$packageCount"
