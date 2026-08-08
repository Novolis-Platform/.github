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
2. Emits **live** GitHub Actions badges (`…/actions/workflows/<file>/badge.svg`) for PR / Merge / Release — these update without regenerating the README
3. Snapshots latest GPR (+ nuget.org when present) package versions and a merge-success count for the summary line
4. Emits **three mutually exclusive tables**: Packages · Releases (no packages) · Other
5. Replaces the marked block in `profile/README.md`

Weekly CI: `.github/workflows/refresh-org-landing.yml` (opens a PR when the matrix changes — mainly for new repos/packages and version bumps).

Cursor agents: see workspace skill `novolis-org-landing`.
