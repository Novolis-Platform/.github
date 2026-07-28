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
2. Queries latest completed workflow conclusions for `pull-request.yml` / `merge.yml` / `release.yml` / `ci.yml`
3. Emits **shields.io** status badges (`brightgreen` when conclusion is `success`)
4. Lists all org NuGet packages on GitHub Packages with latest version as green **GPR** shields
5. Adds nuget.org version shields when the package exists there
6. Replaces the marked block in `profile/README.md`

Cursor agents: see workspace skill `novolis-org-landing`.
