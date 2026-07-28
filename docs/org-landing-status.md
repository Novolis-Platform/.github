# Org landing status matrices

The [organization profile README](../profile/README.md) includes generated **Repository CI** and **Package versions** tables.

## Regenerate

```powershell
pwsh -File scripts/Update-OrgLandingStatus.ps1
```

Requires `gh` authenticated to `Novolis-Platform`.

Do **not** hand-edit content between:

```text
<!-- novolis-org-status:start -->
<!-- novolis-org-status:end -->
```

## What the script does

1. Lists public non-archived org repos and their `.github/workflows/*`
2. Emits PR / Merge / Release Actions badges for consumer workflow files (`pull-request.yml`, `merge.yml`, `release.yml`, `ci.yml`)
3. Lists all org NuGet packages on GitHub Packages with latest version
4. Adds nuget.org shields badges when the package exists there
5. Replaces the marked block in `profile/README.md`

Cursor agents: see workspace skill `novolis-org-landing`.
