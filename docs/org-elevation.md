# Org elevation checklist (landing + nuget.org)

## Done in `.github`

- Product-first org profile (Get started, Featured, trimmed status matrix)
- Weekly `refresh-org-landing.yml` (opens a PR when the matrix changes)
- Org blog URL → https://github.com/orgs/Novolis-Platform/packages
- Featured repo descriptions updated

## Manual: pin popular repos

GitHub has no API to set **organization profile pins**. In the org UI:

1. Open https://github.com/Novolis-Platform
2. Customize pinned repositories
3. Prefer: `novolis-raylib`, `novolis-audio`, `novolis-apps`, `novolis-install`, `novolis-template-dotnet`, `novolis-registry`

(The profile README **Featured** table already lists these.)

## Blocked: nuget.org publish

Flagship GitHub Releases were created:

| Repo | Tag |
|------|-----|
| novolis-messaging | `v2026.1.1` |
| novolis-math | `v2026.1.1` |
| novolis-raylib | `v2026.1.2` |
| novolis-audio | `v2026.1.10` |

Release workflows **failed** because the org has **no** `NUGET_API_KEY` secret (`gh api orgs/.../actions/secrets` → empty).

### Unblock

1. Create a nuget.org API key with push rights for `Novolis.*`
2. Add org secret:

```powershell
gh secret set NUGET_API_KEY --org Novolis-Platform --body "<key>" --visibility private
```

3. Re-run failed release workflows (or delete + recreate the same tags/releases):

```powershell
foreach ($x in @(
  @{r='novolis-messaging'; id='30392210930'},
  @{r='novolis-math'; id='30392215192'},
  @{r='novolis-raylib'; id='30392207885'},
  @{r='novolis-audio'; id='30392209335'}
)) { gh run rerun $x.id -R "Novolis-Platform/$($x.r)" --failed }
```
