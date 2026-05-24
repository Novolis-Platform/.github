# NuGet versioning policy

## Spec: `SDKYEAR.APIBREAK.FEATURE.BUILD`

Example:

```text
2026.1.14.382
```

| Segment    | Rule                                                                                         |
| ---------- | -------------------------------------------------------------------------------------------- |
| `SDKYEAR`  | Runtime baseline year. `2026` means “.NET 10 is the settled baseline.”                       |
| `APIBREAK` | Breaking public API generation. Usually `1`. Increment only for deliberate package breakage. |
| `FEATURE`  | Public release counter. Increment when publishing stable NuGet packages.                     |
| `BUILD`    | CI build/run number. Always increments for internal GitHub package builds.                   |

NuGet supports a fourth numeric revision segment, but SemVer tooling expectations are strongest around `Major.Minor.Patch[-prerelease][+metadata]`; NuGet also normalizes versions and omits fourth-segment zeroes. So use the four-part version for assemblies/files/internal packages, but prefer three-part stable NuGet.org versions. ([Microsoft Learn][1])

## Package version policy

### Internal GitHub Packages

Every successful `main` build may publish:

```text
2026.1.14-ci.382
```

or, if you accept NuGet fourth-segment versions internally:

```text
2026.1.14.382
```

Recommended:

```text
2026.1.14-ci.382
```

Reason: impossible to confuse with a stable public release.

### NuGet.org stable

Only intentional releases publish:

```text
2026.1.14
```

No build number.

### Assembly metadata

```xml
<Version>2026.1.14</Version>
<PackageVersion>2026.1.14</PackageVersion>
<AssemblyVersion>2026.1.0.0</AssemblyVersion>
<FileVersion>2026.1.14.$(BuildNumber)</FileVersion>
<InformationalVersion>2026.1.14+build.$(BuildNumber).sha.$(GitSha)</InformationalVersion>
```

## Version bump heuristics

### Increment `BUILD`

Always, from CI:

```text
github.run_number
```

Use it only for internal packages, file versions, and diagnostics.

### Increment `FEATURE`

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

### Increment `APIBREAK`

When one of these is true:

* public type/member removed
* public signature changed
* behavioral contract changed
* default behavior changes in a way that can break consumers
* target framework baseline changes incompatibly
* package split/rename/namespace breakage

Reset `FEATURE` to `0` after this.

Example:

```text
2026.1.14
2026.1.15
2026.2.0
```

### Increment `SDKYEAR`

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
  "sdkYear": 2026,
  "apiBreak": 1,
  "feature": 14,
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
calculate stableVersion = SDKYEAR.APIBREAK.FEATURE
calculate ciVersion = SDKYEAR.APIBREAK.FEATURE-ci.GITHUB_RUN_NUMBER
restore
build
test
pack with PackageVersion=ciVersion
publish to GitHub Packages on main
upload artifacts
```

### `dotnet-nuget-release.yml`

Does:

```text
read build/version.json
validate main branch
calculate stableVersion
restore
build
test
pack with PackageVersion=stableVersion
publish to NuGet.org
create git tag v{stableVersion}
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
  -p:AssemblyVersion="$SDKYEAR.$APIBREAK.0.0" \
  -p:FileVersion="$SDKYEAR.$APIBREAK.$FEATURE.$GITHUB_RUN_NUMBER" \
  -p:InformationalVersion="$STABLE_VERSION+build.$GITHUB_RUN_NUMBER.sha.$GITHUB_SHA"
```

## Release behavior examples

Current:

```json
{
  "sdkYear": 2026,
  "apiBreak": 1,
  "feature": 14
}
```

CI build `382`:

```text
GitHub Packages: 2026.1.14-ci.382
FileVersion:     2026.1.14.382
InfoVersion:     2026.1.14+build.382.sha.abcd123
```

Stable release:

```text
NuGet.org:       2026.1.14
Git tag:         v2026.1.14
GitHub Release:  2026.1.14
```

Next feature release bumps to:

```json
{
  "sdkYear": 2026,
  "apiBreak": 1,
  "feature": 15
}
```

Breaking release bumps to:

```json
{
  "sdkYear": 2026,
  "apiBreak": 2,
  "feature": 0
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

Internal builds are cheap and infinite:

```text
2026.1.14-ci.382
2026.1.14-ci.383
2026.1.14-ci.384
```

Public releases are intentional and clean:

```text
2026.1.14
2026.1.15
2026.2.0
```

That gives you CalVer/platform signaling, SemVer-like breakage signaling, CI traceability, and NuGet-compatible release hygiene.

[1]: https://learn.microsoft.com/nuget/create-packages/dependency-versions "NuGet Package Version Reference | Microsoft Learn"
[2]: https://github.com/frankhaugen/RoboSharp "GitHub - frankhaugen/RoboSharp: A small C#-inspired programming language that teaches how programming and compilers actually work by controlling a robot on a grid. Higly inspired by Karel and SmallBasic but with a modern .net flair · GitHub"
[3]: https://github.com/frankhaugen/Frank.PulseFlow "GitHub - frankhaugen/Frank.PulseFlow: An in memory messaging system for data-event-driven architecture focused on giving simple interfaces · GitHub"
[4]: https://docs.github.com/en/actions/sharing-automations/reusing-workflows "Reuse workflows - GitHub Docs"
[5]: https://docs.github.com/en/actions/concepts/security/github_token "GITHUB_TOKEN - GitHub Docs"
[6]: https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows "Events that trigger workflows - GitHub Docs"
