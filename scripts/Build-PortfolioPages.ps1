#Requires -Version 7.0
<#
.SYNOPSIS
  Builds the Novolis portfolio documentation site for GitHub Pages.

.DESCRIPTION
  Renders repository docs/plans/brand markdown into static HTML and builds a portfolio
  index from GitHub repository, workflow, and package metadata when gh is available.
  The script intentionally has no npm/Ruby dependency so GitHub Pages publishing stays
  small and predictable.
#>
param(
    [string] $Org = 'Novolis-Platform',
    [string] $OutputDir = '',
    [switch] $SkipGitHub
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot '_site'
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
            '--json', 'name,description,url,homepageUrl,primaryLanguage,repositoryTopics,pushedAt'
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

function Get-MarkdownDocs {
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in @('README.md', 'profile/README.md', 'docs', 'plans', 'brand/README.md')) {
        $full = Join-Path $repoRoot $relative
        if (Test-Path $full -PathType Leaf) {
            $paths.Add((Resolve-Path $full).Path)
        }
        elseif (Test-Path $full -PathType Container) {
            foreach ($file in Get-ChildItem -Path $full -Recurse -Filter '*.md') {
                $paths.Add($file.FullName)
            }
        }
    }
    $wikiRoot = Join-Path $repoRoot 'wiki'
    if (Test-Path $wikiRoot -PathType Container) {
        foreach ($file in Get-ChildItem -Path $wikiRoot -Recurse -Filter '*.md') {
            $paths.Add($file.FullName)
        }
    }

    foreach ($path in ($paths | Sort-Object -Unique)) {
        $content = Get-Content -Raw $path
        $title = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $h1 = [regex]::Match($content, '(?m)^#\s+(.+)$')
        if ($h1.Success) { $title = $h1.Groups[1].Value.Trim() }
        $relative = [System.IO.Path]::GetRelativePath($repoRoot, $path).Replace('\', '/')
        $slug = Slugify ($relative -replace '\.md$', '')
        [pscustomobject]@{
            Title = $title
            RelativePath = $relative
            Slug = $slug
            SourceUrl = "https://github.com/$Org/.github/blob/main/$relative"
            Body = $content
            Group = if ($relative.StartsWith('plans/')) { 'Plans' } elseif ($relative.StartsWith('brand/')) { 'Brand' } elseif ($relative.StartsWith('profile/')) { 'Profile' } elseif ($relative.StartsWith('wiki/')) { 'Wiki' } else { 'Docs' }
        }
    }
}

function Render-Badge {
    param([string] $RepoName, [string] $WorkflowFile)
    $label = [System.IO.Path]::GetFileNameWithoutExtension($WorkflowFile)
    $src = "https://github.com/$Org/$RepoName/actions/workflows/$WorkflowFile/badge.svg"
    $href = "https://github.com/$Org/$RepoName/actions/workflows/$WorkflowFile"
    return "<a class=""badge-link"" href=""$href""><img src=""$src"" alt=""$(Html "$RepoName $label workflow status")""></a>"
}

function Render-PortfolioCard {
    param([object] $Repo)
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
    return @"
<article class="repo-card" data-kind="$(Html $Repo.Kind)" data-search="$(Html (($Repo.Name + ' ' + $Repo.Description + ' ' + ($Repo.Topics -join ' ')).ToLowerInvariant()))">
  $banner
  <div class="repo-card-body">
    <div class="repo-meta">
      <span>$(Html $Repo.Kind)</span>
      <span>$(Html $Repo.Language)</span>
      <span>$packagesCount packages</span>
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
<article class="doc-card" data-doc-group="$(Html $Doc.Group)" data-search="$(Html (($Doc.Title + ' ' + $Doc.RelativePath).ToLowerInvariant()))">
  <span>$(Html $Doc.Group)</span>
  <h3><a href="docs/$(Html $Doc.Slug).html">$(Html $Doc.Title)</a></h3>
  <p>$(Html $Doc.RelativePath)</p>
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
$docs = @(Get-MarkdownDocs)

foreach ($doc in $docs) {
    $article = @"
<article class="article">
  <div class="article-kicker">$(Html $doc.Group) / $(Html $doc.RelativePath)</div>
  <h1>$(Html $doc.Title)</h1>
  <div class="article-actions">
    <a href="$(Html $doc.SourceUrl)">Open source markdown</a>
    <a href="../index.html#docs">Back to docs index</a>
  </div>
  <div class="markdown-body">
    $(Convert-MarkdownToHtml $doc.Body)
  </div>
</article>
"@
    $html = New-PageHtml -Title $doc.Title -Description "Novolis documentation: $($doc.Title)" -Body $article
    Set-Content -Path (Join-Path $outputPath "docs\$($doc.Slug).html") -Value $html -Encoding utf8NoBOM
}

$repoCards = ($repos | ForEach-Object { Render-PortfolioCard $_ }) -join "`n"
$docCards = ($docs | ForEach-Object { Render-DocCard $_ }) -join "`n"
$repoCount = $repos.Count
$docCount = $docs.Count
$packageCount = (@($repos | ForEach-Object { $_.Packages }) | Where-Object { $null -ne $_ }).Count

$indexBody = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="description" content="Novolis portfolio documentation, workflow status, packages, apps, and platform docs."/>
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
        <p class="eyebrow">Portfolio documentation uplink</p>
        <h1>Modern .NET for realtime systems, graphics, games, studios, and simulations.</h1>
        <p class="hero-copy">A single GitHub Pages console for the Novolis library, app, tooling, policy, and package ecosystem. Built from the repository docs corpus and live GitHub portfolio metadata.</p>
        <div class="hero-actions">
          <a href="#portfolio">Explore portfolio</a>
          <a href="#docs">Read docs</a>
          <a href="https://github.com/$Org/.github/actions/workflows/pages.yml"><img src="https://github.com/$Org/.github/actions/workflows/pages.yml/badge.svg" alt="Pages workflow status"></a>
        </div>
      </div>
      <div class="telemetry-panel" aria-label="Portfolio telemetry">
        <div><span>$repoCount</span><strong>repositories</strong></div>
        <div><span>$packageCount</span><strong>NuGet packages</strong></div>
        <div><span>$docCount</span><strong>docs pages</strong></div>
        <div><span>GPR</span><strong>continuous packages</strong></div>
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
        <p class="eyebrow">Repository wiki corpus</p>
        <h2>Docs</h2>
      </div>
      <div class="controls">
        <label class="search-box">
          <span>Search</span>
          <input type="search" id="docSearch" placeholder="versioning, brand, raylib, bootstrap"/>
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
Write-Host "  repos=$repoCount docs=$docCount packages=$packageCount"
