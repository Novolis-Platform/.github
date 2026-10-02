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
2. Records the latest completed `merge.yml` and `release.yml` run that was not cancelled only because a newer run superseded it. Libraries publish packages from merge, so Failed lists that merge when it failed or was cancelled. Apps publish APKs and installers from release, so a failed app release is listed too. Shipped lists an app GitHub Release only when it published assets. A library tag with no installers is not a ship.
3. Records the latest GitHub Release per repository, the downloadable assets on shipped app releases, plus the highest GPR and nuget.org versions
4. Writes that snapshot to `site/status.json` and into `profile/README.md` as failed runs, shipped releases, latest app downloads, and the inventory

Merge and release workflows call `dispatch-org-landing`, which sends `repository_dispatch` `landing-status` to this repo. That needs organization secret `NOVOLIS_LANDING_TOKEN` (Actions: write on `Novolis-Platform/.github`), or `NOVOLIS_GPR_TOKEN` with the same access, available to the repositories that run those workflows. `refresh-org-landing.yml` then rewrites `site/status.json`. A commit that only changes that file does not rebuild the docs site. The docs home reads `site/status.json` from `main` when the page opens. The daily schedule is the backup when no workflow asked.

Cursor agents: see workspace skill `novolis-org-landing`.

Profile tokens, repo banners, and `site/repo-catalog.json` are generated — do not hand-edit them:

```powershell
pwsh -File d:\novolis\novolis-governance\scripts\Export-GraphicalProfile.ps1
pwsh -File d:\novolis\novolis-governance\scripts\Upgrade-RepoMarketingReadmes.ps1 -SkipReadmes
pwsh -File d:\novolis\novolis-governance\scripts\verify-graphical-profile.ps1
```
