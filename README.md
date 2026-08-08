<!-- novolis-marketing:start -->
<p align="center">
  <a href="https://github.com/Novolis-Platform">
    <img src="https://raw.githubusercontent.com/Novolis-Platform/.github/main/brand/logo-brand-transparent.svg" width="360" alt="Novolis"/>
  </a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Novolis-Platform/.github/main/brand/banners/github-org.svg" width="100%" alt=".github"/>
</p>

<p align="center">
  <strong>Org home and brand</strong><br/>
  Organization profile README, brand assets, and landing status generators.
</p>

<p align="center">
  <a href="https://github.com/Novolis-Platform"><img src="https://img.shields.io/badge/org-Novolis--Platform-111827" alt="org"/></a>
  <a href="https://github.com/orgs/Novolis-Platform/packages"><img src="https://img.shields.io/badge/packages-GitHub%20Packages-0a7ea3?logo=nuget" alt="packages"/></a>
  <a href="https://github.com/Novolis-Platform/.github/actions/workflows/pages.yml"><img src="https://github.com/Novolis-Platform/.github/actions/workflows/pages.yml/badge.svg" alt="Publish portfolio docs"/></a>
  <a href="https://github.com/Novolis-Platform/.github/actions/workflows/refresh-org-landing.yml"><img src="https://github.com/Novolis-Platform/.github/actions/workflows/refresh-org-landing.yml/badge.svg" alt="Refresh org landing status"/></a>
</p>

<p align="center">
  <a href="https://nuget.pkg.github.com/Novolis-Platform/index.json"><code>https://nuget.pkg.github.com/Novolis-Platform/index.json</code></a>
  ·
  <a href="https://novolis-platform.github.io/.github/">Portfolio docs</a>
  ·
  <a href="https://github.com/Novolis-Platform/.github/blob/main/profile/README.md">Org landing</a>
  ·
  <a href="https://github.com/Novolis-Platform/novolis-governance">Governance</a>
</p>

---
<!-- novolis-marketing:end -->
# Novolis-Platform/.github

Organization profile and community defaults for [Novolis-Platform](https://github.com/Novolis-Platform).

The organization README is in [`profile/README.md`](profile/README.md) and appears on the org home page.

Brand assets live in [`brand/`](brand/):

- [`brand/logo-brand-transparent.svg`](brand/logo-brand-transparent.svg) — primary full lockup
- [`brand/logo-icon.svg`](brand/logo-icon.svg) / [`brand/favicon.svg`](brand/favicon.svg) — iconographic mark (no wordmark)
- [`brand/logo-icon.png`](brand/logo-icon.png) / [`brand/logo-icon.ico`](brand/logo-icon.ico) — NuGet / Windows icons
- [`brand/banners/`](brand/banners/) — per-repo marketing hero SVGs for GitHub READMEs

Sync copies into all `novolis-*` repos:

```powershell
pwsh -File scripts/Sync-BrandIcons.ps1
```

## Org landing status matrices

CI badges and package versions on the org profile are generated — do not hand-edit the marked block in `profile/README.md`.

```powershell
pwsh -File scripts/Update-OrgLandingStatus.ps1
```

Requires `gh` authenticated to the org.

## Portfolio docs site

GitHub Pages is published from `.github/workflows/pages.yml` to https://novolis-platform.github.io/.github/.

```powershell
pwsh -File d:\novolis\.github\scripts\Build-PortfolioPages.ps1
```

The builder ingests markdown from **every** public org repository:

| Source | Included |
|--------|----------|
| Root | `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `AGENTS.md` |
| Guides | `docs/**/*.md`, `wiki/**/*.md` |
| Packages | `src/**/README.md` |
| Org home | `.github` profile/docs/plans/brand corpus |

Local sibling checkouts under the workspace root are preferred; CI fetches missing trees/content from GitHub. Live repository, workflow, and package metadata are added when `gh` is authenticated. Weekly schedule keeps the corpus fresh.

## Repositories

| Repository | Purpose |
|------------|---------|
| [novolis-governance](https://github.com/Novolis-Platform/novolis-governance) | Org-wide policies and maintainer guides |
| [novolis-workflows](https://github.com/Novolis-Platform/novolis-workflows) | Reusable GitHub Actions and composite actions |
| [novolis-template-dotnet](https://github.com/Novolis-Platform/novolis-template-dotnet) | Canonical .NET package/tool repo template |
| [novolis-registry](https://github.com/Novolis-Platform/novolis-registry) | Static package and app registry |
| [novolis-install](https://github.com/Novolis-Platform/novolis-install) | Cross-platform `novolis` CLI installer |
| [novolis-apps](https://github.com/Novolis-Platform/novolis-apps) | Desktop apps + Inno installers (`Novolis.Avalonia.Packaging.Inno`) |
