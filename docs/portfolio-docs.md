# Portfolio documentation site

Published at https://novolis-platform.github.io/.github/ from [`.github/workflows/pages.yml`](../.github/workflows/pages.yml).

## Build

```powershell
pwsh -File d:\novolis\.github\scripts\Build-PortfolioPages.ps1
```

Optional parameters:

| Parameter | Purpose |
|-----------|---------|
| `-WorkspaceRoot` | Parent folder containing sibling `novolis-*` checkouts (default: parent of `.github`) |
| `-SkipGitHub` | Skip live `gh` portfolio/package queries; still reads local sibling docs |
| `-FetchThrottle` | Parallel raw-fetch concurrency (default `16`) |
| `-OutputDir` | Must stay under the `.github` repo (default `_site`) |

## Corpus rules

For each public, non-archived org repository the builder includes:

1. Root `README.md` / `CONTRIBUTING.md` / `SECURITY.md` / `CHANGELOG.md` / `AGENTS.md`
2. Everything under `docs/**/*.md` and `wiki/**/*.md`
3. Package READMEs at `src/**/README.md`
4. For `.github` only: `profile/`, `docs/`, `plans/`, `brand/README.md`, root README

Excluded: `bin/`, `obj/`, `node_modules/`, `.cursor/`, and `novolis-experimental/source/` (third-party dumps). Files larger than 500 KB are skipped.

## Refresh cadence

- Push to `.github` `main`
- Manual `workflow_dispatch`
- Weekly Monday cron (re-pulls docs from all repos)
