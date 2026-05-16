# Prep Work: Novolis Organization Bootstrap

## Objective

Prepare the organization, templates, workflows, publishing model, and distribution model before moving any existing libraries.

No existing library/package repos should be moved yet.

1. Create organization baseline

## Create GitHub organization

* Create the public GitHub organization.
* Configure public organization profile.
* Add organization README.
* Add short ecosystem description.
* Add links to:

  * contribution policy
  * security policy
  * package registry docs
  * roadmap

## Configure organization settings

Enable:

* Require 2FA for members.
* Secret scanning.
* Push protection.
* Dependabot alerts.
* Dependabot security updates.
* Private vulnerability reporting.
* GitHub Discussions if useful.
* Restrict base permissions to read-only.

Create teams:

|Team|Purpose|
|-|-|
|`owners`|Org ownership only|
|`maintainers`|Repo maintainers|
|`contributors`|Trusted contributors|
|`automation`|GitHub Apps / bots only|

---

# 2. Create governance repo

Create:

```txt
novolis-governance
````

Purpose:

* Org-wide policies.
* Contribution model.
* Naming rules.
* Package rules.
* Security policy.
* Release policy.
* Maintainer expectations.

Initial files:

```txt
README.md
CONTRIBUTING.md
SECURITY.md
CODE_OF_CONDUCT.md
SUPPORT.md
docs/
  naming.md
  repository-policy.md
  package-policy.md
  release-policy.md
  security-policy.md
  contribution-policy.md
  maintainer-guide.md
```

---

# 3. Define naming policy

Document in:

```txt
novolis-governance/docs/naming.md
```

Rules:

## Repositories

Use:

```txt
novolis-<domain>
```

Examples:

```txt
novolis-math
novolis-physics
novolis-raylib
novolis-transports
novolis-messaging
novolis-security
novolis-codegen
novolis-analyzers
novolis-storage
```

Rules:

* lowercase
* kebab-case
* no personal names
* no `core`
* no `common`
* no `utils`
* no `shared`
* no vague junk-drawer names

## NuGet packages

Use:

```txt
Novolis.<Domain>
```

Examples:

```txt
Novolis.Math
Novolis.Physics
Novolis.Raylib
Novolis.Transports
Novolis.Messaging
Novolis.Security
Novolis.CodeGen
Novolis.Analyzers
Novolis.Storage
```

Adapters/providers use suffixes:

```txt
Novolis.Storage.SqlServer
Novolis.Messaging.AzureServiceBus
Novolis.Transports.Quic
Novolis.Testing.Xunit
```

---

# 4. Create repo template

Create:

```txt
novolis-template-dotnet
```

Purpose:

* Canonical template for all package/tool repos.

Initial structure:

```txt
.github/
  workflows/
    ci.yml
    release.yml
  ISSUE_TEMPLATE/
    bug_report.yml
    feature_request.yml
  pull_request_template.md

docs/
src/
tests/
eng/

.editorconfig
.gitattributes
.gitignore
Directory.Build.props
Directory.Packages.props
global.json
NuGet.config
README.md
LICENSE
SECURITY.md
CONTRIBUTING.md
CODE_OF_CONDUCT.md
SUPPORT.md
```

The template must support:

* library repo
* CLI tool repo
* analyzer repo
* game/app repo
* template repo

Do not over-specialize yet.

---

# 5. Create workflow infrastructure repo

Create:

```txt
novolis-workflows
```

Purpose:

* Central reusable GitHub workflows.
* Composite actions.
* Standard release behavior.

Structure:

```txt
.github/
  workflows/
    dotnet-ci.yml
    dotnet-pack.yml
    dotnet-publish-nuget.yml
    desktop-app-release.yml
    registry-pr.yml

actions/
  setup-dotnet/
  restore/
  build/
  test/
  pack/
  detect-changes/
  validate-package/
  publish-nuget/
  create-release-artifacts/
  compute-checksums/
  update-registry/
```

Required behavior:

* Build on PR.
* Test on PR.
* Pack on main.
* Publish only from approved release path.
* No publishing from forks.
* No publishing from untrusted PRs.
* Default workflow permissions are read-only.
* Escalate permissions only per job.

Default permissions:

```yaml
permissions:
  contents: read
```

Publishing permissions only where needed:

```yaml
permissions:
  contents: read
  id-token: write
```

---

# 6. Define package publishing policy

Document in:

```txt
novolis-governance/docs/package-policy.md
```

Rules:

* Prefer NuGet Trusted Publishing/OIDC.
* Do not store broad NuGet API keys.
* Do not publish from pull requests.
* Do not publish from forks.
* Publish only from:

  * GitHub Release
  * signed version tag
  * manually approved environment
* Use GitHub Environment:

```txt
nuget.org
```

Environment requirements:

* maintainer approval
* no automatic deployment from random branch
* no secret exposure to PRs

Package metadata must include:

```xml
<PackageId>Novolis.X</PackageId>
<Title>Novolis X</Title>
<Description>...</Description>
<Authors>Novolis</Authors>
<RepositoryUrl>...</RepositoryUrl>
<RepositoryType>git</RepositoryType>
<PackageLicenseExpression>MIT</PackageLicenseExpression>
<PackageReadmeFile>README.md</PackageReadmeFile>
<PublishRepositoryUrl>true</PublishRepositoryUrl>
<ContinuousIntegrationBuild>true</ContinuousIntegrationBuild>
<EmbedUntrackedSources>true</EmbedUntrackedSources>
<IncludeSymbols>true</IncludeSymbols>
<SymbolPackageFormat>snupkg</SymbolPackageFormat>
```

---

# 7. Define versioning policy

Document in:

```txt
novolis-governance/docs/release-policy.md
```

Initial versioning:

```txt
0.x.y while unstable
SemVer after 1.0
-preview.N for previews
```

Rules:

* Package version must match release tag.
* Stable packages only from stable tags.
* Preview packages may publish from preview tags.
* Do not auto-generate clever versions in v0.
* Manual version bump first.
* Automate later only after the release process is stable.

Tag examples:

```txt
v0.1.0
v0.2.0-preview.1
```

---

# 8. Define change detection model

Create a standard package manifest file:

```txt
.novolis/packages.json
```

Example:

```json
{
  "packages": {
    "Novolis.Storage": {
      "project": "src/Novolis.Storage/Novolis.Storage.csproj",
      "paths": [
        "src/Novolis.Storage/**",
        "tests/Novolis.Storage.Tests/**",
        "Directory.Build.props",
        "Directory.Packages.props",
        "global.json"
      ]
    }
  }
}
```

Purpose:

* Detect affected packages.
* Avoid publishing unchanged packages.
* Avoid path-guessing.
* Support multi-package repos later.

Rules:

* Workflows read `.novolis/packages.json`.
* CI may build all.
* Publish only affected packages.
* Publish only if package version changed.

---

# 9. Create installer/distribution repos

Create:

```txt
novolis-install
novolis-registry
novolis-installer-inno
```

## `novolis-install`

Purpose:

* Cross-platform user-space installer/launcher.
* Installed as a .NET global tool.

Command:

```bash
novolis
```

Initial commands:

```bash
novolis search
novolis info <id>
novolis install <id>
novolis install <id> --channel preview
novolis install <id> --installer
novolis update
novolis update <id>
novolis list
novolis remove <id>
novolis doctor
```

Install locations:

```txt
Windows: %LOCALAPPDATA%Novolis
Linux:   ~/.local/share/novolis
macOS:   ~/Library/Application Support/Novolis
```

Shim locations:

```txt
Windows: %USERPROFILE%.novolisbin
Linux:   ~/.local/bin or ~/.novolis/bin
macOS:   ~/.novolis/bin
```

## `novolis-registry`

Purpose:

* Static package/app registry.
* No server required initially.

Structure:

```txt
index.json
packages/
  example-tool.json
  example-game.json
schemas/
  package.schema.json
```

Registry entries support:

* dotnet tools
* dotnet templates
* portable apps
* Windows Inno installers
* asset packs

## `novolis-installer-inno`

Purpose:

* Shared Inno Setup templates.
* Standard Windows installer adapter.

Structure:

```txt
inno/
  Novolis.Common.iss
  Novolis.Game.iss
  Novolis.Tool.iss
  Novolis.DesktopApp.iss

scripts/
  Build-InnoInstaller.ps1
  Generate-AppId.ps1
  Resolve-Version.ps1

docs/
  installer-contract.md
```

---

# 10. Define app installer contract

Standard file in app/game repos:

```txt
installer/app.installer.json
```

Example:

```json
{
  "id": "novolis-starfighter",
  "name": "Novolis Starfighter",
  "publisher": "Novolis",
  "version": "0.1.0",
  "executable": "Novolis.Starfighter.exe",
  "installMode": "perUser",
  "shortcuts": {
    "desktop": true,
    "startMenu": true
  },
  "fileAssociations": [],
  "protocols": [],
  "requiresAdmin": false
}
```

Default:

```txt
per-user install
```

Avoid:

* admin-only install
* registry-heavy behavior
* arbitrary post-install scripts
* uncontrolled PATH mutation

---

# 11. Define registry security model

Minimum v0 rules:

* HTTPS downloads only.
* SHA-256 required for every artifact.
* Registry updates via pull request.
* No direct mutation from app repos.
* No arbitrary install scripts.
* No unsigned registry releases once signing is introduced.
* Manifest schema validation in CI.

Later:

* registry signatures
* artifact signatures
* Authenticode for Windows
* notarization for macOS
* SBOM/provenance enforcement

---

# 12. Create initial empty/basic repos

Create empty/template-based repos only.

Do not move libraries yet.

Create:

```txt
novolis-math
novolis-physics
novolis-machinelearning
novolis-raylib
novolis-transports
novolis-security
novolis-messaging
novolis-codegen
novolis-analyzers
novolis-storage
novolis-testing
novolis-templates
```

Each repo should contain:

* README
* license
* contribution docs
* security docs
* CI
* package metadata placeholder
* `.novolis/packages.json`
* empty `src/`
* empty `tests/`

README should clearly state:

```txt
This repository is reserved for the Novolis <domain> package.
Implementation will be migrated or built in later steps.
```

---

# 13. Configure branch rulesets

For each repo:

Protect:

```txt
main
```

Require:

* pull request before merge
* at least 1 approval
* status checks
* conversation resolution
* linear history
* no force push
* no deletion

For sensitive files, require stronger review:

```txt
.github/workflows/**
.github/actions/**
Directory.Build.props
Directory.Packages.props
NuGet.config
.novolis/**
installer/**
```

Recommended:

* 2 approvals for workflow/release/package files
* owner/maintainer approval for publishing changes

---

# 14. Configure NuGet ownership

Before publishing anything:

* Create/prepare NuGet organization.
* Reserve `Novolis.*` package IDs where practical.
* Configure trusted publishing for first test package.
* Ensure at least two maintainers have access.
* Avoid personal-only package ownership.

Do not publish real migrated libraries yet.

Optional dry-run package:

```txt
Novolis.TemplateSmokeTest
```

Use it only to validate pipeline behavior.

---

# 15. Build smoke-test repo

Create:

```txt
novolis-smoketest
```

Purpose:

* Validate template.
* Validate CI.
* Validate package build.
* Validate NuGet publishing path.
* Validate registry PR path.
* Validate installer flow.

This repo can contain:

* tiny class library
* tiny CLI tool
* tiny portable app
* dummy registry entry

Once infrastructure is proven, archive or keep private/internal.

---

# 16. Define migration checklist

Create:

```txt
novolis-governance/docs/migration-checklist.md
```

Checklist for later library movement:

```txt
1. Identify old source repo.
2. Decide move vs extract vs rebuild.
3. Create issue in target repo.
4. Copy only useful source.
5. Normalize namespace.
6. Normalize package ID.
7. Update README.
8. Add tests.
9. Add package metadata.
10. Add .novolis/packages.json.
11. Run CI.
12. Create preview release.
13. Validate NuGet package.
14. Mark old repo archived or redirected.
15. Add migration note in old README.
```

Explicit rule:

```txt
Do not transfer old repository history by default.
Prefer clean curated repos unless history is legally or technically important.
```

---

# 17. Define repo status labels

Standard labels:

```txt
status:reserved
status:bootstrap
status:active
status:experimental
status:deprecated
status:archived
area:build
area:docs
area:security
area:packaging
area:installer
area:api
area:tests
good first issue
help wanted
breaking-change
```

---

# 18. Define contribution safety

Policy:

* External PRs allowed.
* Fork PRs run unprivileged CI only.
* No secrets for PRs from forks.
* Maintainers trigger privileged publish/release flows.
* Dependabot PRs require review for workflow/package changes.
* Generated files must be marked clearly.
* Large changes should start as GitHub Discussions or issues.

---

# 19. Define documentation minimum

Every repo must have:

```txt
README.md
docs/getting-started.md
docs/design.md
docs/release.md
```

Minimum README sections:

```md
# Project Name

## What it is

## Current status

## Install

## Quick start

## Documentation

## Contributing

## Security
```

For reserved repos:

```md
## Current status

This repository is reserved as part of the Novolis ecosystem bootstrap.
Implementation has not been migrated yet.
```

---

# 20. Completion criteria

Prep work is done when:

* Organization exists.
* Governance repo exists.
* Template repo exists.
* Workflow repo exists.
* Installer repos exist.
* Registry repo exists.
* Initial reserved repos exist.
* Branch rules are configured.
* CI works on template repos.
* Smoke-test package can build.
* NuGet trusted publishing has been validated.
* Registry PR flow has been validated.
* No real library migration has started.

---

# Non-goals

Do not yet:

* move existing library repos
* rename existing packages
* publish production packages
* build the game framework
* build the physics library
* create polished installers
* implement complex version automation
* support third-party registry packages
* support arbitrary install scripts
* support system-wide installs by default

