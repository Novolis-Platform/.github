# Novolis-Platform/.github

Organization profile and community defaults for [Novolis-Platform](https://github.com/Novolis-Platform).

The organization README is in [`profile/README.md`](profile/README.md) and appears on the org home page.

Brand assets live in [`brand/`](brand/):

- [`brand/logo-brand-transparent.svg`](brand/logo-brand-transparent.svg) — primary full lockup
- [`brand/logo-icon.svg`](brand/logo-icon.svg) / [`brand/favicon.svg`](brand/favicon.svg) — iconographic mark (no wordmark)
- [`brand/logo-icon.png`](brand/logo-icon.png) / [`brand/logo-icon.ico`](brand/logo-icon.ico) — NuGet / Windows icons

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

## Repositories

| Repository | Purpose |
|------------|---------|
| [novolis-governance](https://github.com/Novolis-Platform/novolis-governance) | Org-wide policies and maintainer guides |
| [novolis-workflows](https://github.com/Novolis-Platform/novolis-workflows) | Reusable GitHub Actions and composite actions |
| [novolis-template-dotnet](https://github.com/Novolis-Platform/novolis-template-dotnet) | Canonical .NET package/tool repo template |
| [novolis-registry](https://github.com/Novolis-Platform/novolis-registry) | Static package and app registry |
| [novolis-install](https://github.com/Novolis-Platform/novolis-install) | Cross-platform `novolis` CLI installer |
| [novolis-apps](https://github.com/Novolis-Platform/novolis-apps) | Desktop apps + Inno installers (`Novolis.Avalonia.Packaging.Inno`) |
