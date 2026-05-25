# NuGet versioning policy

## Spec: `YEAR.MAJOR.MINOR.BUILD`

Example:

```text
2026.1.1.351
```

Every GitHub Package and nuget.org package uses this **four-part numeric** version. No prerelease labels (`-ci`), no `+metadata` text.

| Segment | JSON field | Rule |
| ------- | ---------- | ---- |
| `YEAR` | `year` | Platform generation year (e.g. `2026` = .NET 10 baseline) |
| `MAJOR` | `major` | Breaking public API generation; bump only for deliberate breakage |
| `MINOR` | `minor` | Release line; bump manually before an intentional release |
| `BUILD` | *(CI only)* | `github.run_number`; never committed |

Legacy JSON names (`sdkYear`, `apiBreak`, `feature`) are still read by CI scripts during migration.

## Package version policy

### GitHub Packages and nuget.org

Same version everywhere:

```text
2026.1.1.351
2026.1.1.366
```

`BUILD` distinguishes every CI run on the same `YEAR.MAJOR.MINOR` line.

### Assembly metadata

```xml
<Version>2026.1.1.351</Version>
<PackageVersion>2026.1.1.351</PackageVersion>
<AssemblyVersion>2026.1.0.0</AssemblyVersion>
<FileVersion>2026.1.1.351</FileVersion>
<InformationalVersion>2026.1.1.351</InformationalVersion>
```

## Version bump heuristics

### Increment `BUILD`

Always, from CI:

```text
github.run_number
```

Use it only for internal packages, file versions, and diagnostics.

### Increment `MINOR`

When one of these is true:

* public API added
* behavior improved without breakage
* meaningful package release
* dependency baseline changed non-breakingly
* docs/samples materially improved for package consumers

Do not increment for:

* failed builds
* internal-only CI retries
* README typo
* formatting
* test-only changes

### Increment `MAJOR`

When one of these is true:

* public type/member removed
* public signature changed
* behavioral contract changed
* default behavior changes in a way that can break consumers
* target framework baseline changes incompatibly
* package split/rename/namespace breakage

Reset `MINOR` to `0` after this.

Example (deliberate breaking-API generation only — **do not** bump `major` to `2` on the live platform without governance approval):

```text
2026.1.14
2026.1.15
2026.2.0   ← only after setting "major": 2 in build/version.json (forbidden for routine releases)
```

Until that approval exists, every `novolis-*` package repo must keep `"major": 1` and `"minor": 1` (platform line **`2026.1.1`**, packages **`2026.1.1.{run}`**). A mistaken `major: 2` publishes **`2026.2.*`**, which is not the current platform line.

### Increment `YEAR`

When the project intentionally moves to the next settled .NET baseline.

Example:

```text
2026.x.x = .NET 10 baseline
2027.x.x = .NET 11/12 chosen baseline, depending on policy
```

I would not blindly map every calendar year to every .NET version. Make `SDKYEAR` mean “platform generation,” not “wall clock.”

## Required repo structure

Your repos already point in the right direction: RoboSharp has `Directory.Build.props`, `Directory.Build.targets`, `Directory.Packages.props`, `.github`, `eng`, `src`, `tests`, and `.slnx` structure; it also targets .NET 10 in its README and `global.json` flow. ([GitHub][2]) PulseFlow is older/archived, but useful as package infrastructure inspiration: it has `Directory.Build.props`, `Directory.Build.targets`, `.github/workflows`, README/package metadata, license, icon, and NuGet-facing docs. ([GitHub][3])

Recommended standard:

```text
/
  global.json
  Directory.Build.props
  Directory.Build.targets
  Directory.Packages.props
  build/
    version.json
    release-notes.md
  src/
  tests/
  .github/
    workflows/
      ci.yml
      release.yml
```

## `build/version.json`

> **Novolis:** Version intent lives under repo-root `build/` (not `eng/`, which is ambiguous). Reusable workflows: `Novolis-Platform/novolis-workflows`. Stable release trigger: GitHub Release published (`v2026.1.0`).

```json
{
  "year": 2026,
  "major": 1,
  "minor": 1,
  "dotnetBaseline": "net10.0",
  "publicPackage": true
}
```

This file is the human-owned version intent.

CI owns `BUILD`.

## Repo workflow: `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [ main ]

permissions:
  contents: read
  packages: write

jobs:
  dotnet:
    uses: frankhaugen/shared-workflows/.github/workflows/dotnet-nuget-ci.yml@main
    with:
      solution: RoboSharp.slnx
      version-file: build/version.json
      publish-internal-packages: ${{ github.ref == 'refs/heads/main' }}
    secrets: inherit
```

Reusable workflows are the correct fit here; GitHub supports `workflow_call` specifically for calling workflows from other workflows. ([GitHub Docs][4]) The `GITHUB_TOKEN` is generated per job and should be given only needed permissions, such as `contents: read` and `packages: write` for GitHub Packages publishing. ([GitHub Docs][5])

## Repo workflow: `.github/workflows/release.yml`

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      release_kind:
        type: choice
        required: true
        options:
          - feature
          - breaking
          - republish-current

permissions:
  contents: write
  packages: write

jobs:
  release:
    uses: frankhaugen/shared-workflows/.github/workflows/dotnet-nuget-release.yml@main
    with:
      solution: RoboSharp.slnx
      version-file: build/version.json
      release-kind: ${{ inputs.release_kind }}
      publish-nuget-org: true
      create-github-release: true
    secrets: inherit
```

Use `workflow_dispatch` for intentional releases; GitHub supports manual workflow inputs for this. ([GitHub Docs][6])

## Shared workflow responsibilities

### `dotnet-nuget-ci.yml`

Does:

```text
read build/version.json
read build/version.json (year, major, minor)
calculate packageVersion = YEAR.MAJOR.MINOR.GITHUB_RUN_NUMBER
restore
build
test
pack with PackageVersion=packageVersion
publish to GitHub Packages on main
upload artifacts
```

### `dotnet-nuget-release.yml`

Does:

```text
read build/version.json
validate main branch
calculate packageVersion = YEAR.MAJOR.MINOR.GITHUB_RUN_NUMBER
restore
build
test
pack with PackageVersion=packageVersion
publish to NuGet.org
create git tag v{YEAR.MAJOR.MINOR} or v{packageVersion}
create GitHub Release
optionally bump build/version.json by release_kind
open PR or commit bump
```

## MSBuild standard

In `Directory.Build.props`:

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>

    <ContinuousIntegrationBuild Condition="'$(GITHUB_ACTIONS)' == 'true'">true</ContinuousIntegrationBuild>
    <Deterministic>true</Deterministic>

    <RepositoryType>git</RepositoryType>
    <RepositoryUrl>https://github.com/frankhaugen/$(MSBuildProjectName)</RepositoryUrl>

    <PackageRequireLicenseAcceptance>false</PackageRequireLicenseAcceptance>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
```

CI passes versions explicitly:

```bash
dotnet pack "$SOLUTION" \
  -c Release \
  -p:Version="$PACKAGE_VERSION" \
  -p:PackageVersion="$PACKAGE_VERSION" \
  -p:AssemblyVersion="$YEAR.$MAJOR.0.0" \
  -p:FileVersion="$YEAR.$MAJOR.$MINOR.$GITHUB_RUN_NUMBER" \
  -p:InformationalVersion="$YEAR.$MAJOR.$MINOR.$GITHUB_RUN_NUMBER"
```

## Release behavior examples

Current:

```json
{
  "year": 2026,
  "major": 1,
  "minor": 1
}
```

CI build `351`:

```text
GitHub Packages / nuget.org: 2026.1.1.351
AssemblyVersion:             2026.1.0.0
FileVersion:                 2026.1.1.351
```

CI build `366` (same MINOR line):

```text
Package version: 2026.1.1.366
```

Next minor release bumps to:

```json
{
  "year": 2026,
  "major": 1,
  "minor": 2
}
```

Breaking major release bumps to:

```json
{
  "year": 2026,
  "major": 2,
  "minor": 0
}
```

## Required GitHub setup

Use:

```text
shared-workflows repo
  .github/workflows/dotnet-nuget-ci.yml
  .github/workflows/dotnet-nuget-release.yml
  .github/actions/read-version/
  .github/actions/dotnet-pack-versioned/
```

Repo secrets:

```text
NUGET_API_KEY
```

Repo/org variables:

```text
DOTNET_VERSION = 10.0.x
NUGET_SOURCE_GITHUB = https://nuget.pkg.github.com/frankhaugen/index.json
```

GitHub environments:

```text
github-packages
nuget-org
```

Put approval only on `nuget-org`.

## The core rule

Every publish uses the same numeric shape:

```text
2026.1.1.351
2026.1.1.352
2026.1.1.366
```

`BUILD` is always `github.run_number`. Bump `minor` or `major` in `build/version.json` only when you intend a new release line.

[1]: https://learn.microsoft.com/nuget/create-packages/dependency-versions "NuGet Package Version Reference | Microsoft Learn"
[2]: https://github.com/frankhaugen/RoboSharp "GitHub - frankhaugen/RoboSharp: A small C#-inspired programming language that teaches how programming and compilers actually work by controlling a robot on a grid. Higly inspired by Karel and SmallBasic but with a modern .net flair · GitHub"
[3]: https://github.com/frankhaugen/Frank.PulseFlow "GitHub - frankhaugen/Frank.PulseFlow: An in memory messaging system for data-event-driven architecture focused on giving simple interfaces · GitHub"
[4]: https://docs.github.com/en/actions/sharing-automations/reusing-workflows "Reuse workflows - GitHub Docs"
[5]: https://docs.github.com/en/actions/concepts/security/github_token "GITHUB_TOKEN - GitHub Docs"
[6]: https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows "Events that trigger workflows - GitHub Docs"
