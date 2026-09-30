# Org landing status matrices

The [organization profile README](../profile/README.md) includes generated **Repository CI** and **Package versions** tables.

## Regenerate

```powershell
pwsh -File scripts/Update-OrgLandingStatus.ps1
```

Requires `gh` authenticated to `Novolis-Platform`. Then **commit and push** to `main` so https://github.com/Novolis-Platform updates.

Do **not** hand-edit content between:

```text
<!-- novolis-org-status:start -->
<!-- novolis-org-status:end -->
```

## What the script does

1. Lists public non-archived org repos and their `.github/workflows/*`
2. Records the latest completed `merge.yml` and `release.yml` run, including the first failing check annotation
3. Records the latest GitHub Release per repository, plus the highest GPR and nuget.org versions
4. Writes that snapshot to `site/status.json` and into `profile/README.md` as failed runs, shipped releases, and the inventory

Daily CI: `.github/workflows/refresh-org-landing.yml` pushes `main` when the snapshot changes. The portfolio site rebuild (`pages.yml`) renders the same JSON.

Cursor agents: see workspace skill `novolis-org-landing`.

Profile tokens, repo banners, and `site/repo-catalog.json` are generated — do not hand-edit them:

```powershell
pwsh -File d:\novolis\novolis-governance\scripts\Export-GraphicalProfile.ps1
pwsh -File d:\novolis\novolis-governance\scripts\Upgrade-RepoMarketingReadmes.ps1 -SkipReadmes
pwsh -File d:\novolis\novolis-governance\scripts\verify-graphical-profile.ps1
```
