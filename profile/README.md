<p align="center">
  <img src="https://raw.githubusercontent.com/Novolis-Platform/.github/main/brand/logo-brand-transparent.svg" width="420" alt="Novolis"/>
</p>

# Novolis 👋

Modern .NET ecosystem tooling for realtime systems, graphics, runtime infrastructure, experimentation, and whatever else seems like a good idea at 02:00.

---

## Why “Novolis”? ✨

The name was designed to feel:

- modern, but not trendy
- technical, but still human
- platform-oriented, not product-oriented
- professional without sounding corporate
- memorable without needing abbreviations

`Novo` subtly hints at ideas like:

- renewal
- iteration
- evolution
- modern systems

while `-olis` was chosen mostly because it sounds structured, calm, and conversationally natural.

Importantly:

```text
"we use Novolis.Hosting internally"
```

sounds like software infrastructure, not a crypto exchange or an anime MMO.

That matters 😄

---

## Naming Philosophy 🧭

Novolis projects aim to be:

* easy to pronounce
* easy to remember
* pleasant to say in meetings
* usable in both OSS and enterprise environments

We intentionally avoid names that sound like:

* 🚀 startup buzzwords
* 🪙 crypto projects
* 🧙 fantasy spellbooks
* 🔥 “next-gen ultra hyper” frameworks

---

## Ecosystem 🌌

The long-term idea is an ecosystem of modular packages and tooling:

```text
Novolis.Raylib
Novolis.Hosting
Novolis.Game
Novolis.Native
Novolis.Gui
```

and potentially much more over time.

The ecosystem is intentionally broad and technology-neutral.

Games, tools, rendering, simulation, diagnostics, networking, experiments — all fair game.

---

## Design Ideas 🛠️

Some recurring themes:

* progressive complexity
* composable architecture
* modern .NET patterns
* low ceremony
* native escape hatches
* practical developer experience

No forced mega-engine architecture.

No mandatory ECS religion.

No “you must do things our way” energy.

---

## Build, package & release 📦

Package libraries use a three-stage pipeline:

| Stage | Trigger | What happens |
|-------|---------|--------------|
| Build | PR to `main` (`pull-request.yml`) | Restore, build, test — no publish |
| Package | Push to `main` (`merge.yml`) | Pack `YEAR.MAJOR.MINOR.{run}` → [GitHub Packages](https://github.com/orgs/Novolis-Platform/packages) |
| Release | GitHub Release published (`release.yml`) | Same version shape → [nuget.org](https://www.nuget.org/) + release assets |

Versions are four-part numeric only (`2026.1.1.351`) — see [nuget-versioning.md](https://github.com/Novolis-Platform/.github/blob/main/docs/nuget-versioning.md). Desktop apps (`novolis-apps`) ship zip/installers via GitHub Releases instead of nuget.org.

---

## Brand

The Novolis logo is kept as a transparent, resolution-independent SVG in [`brand/logo-brand-transparent.svg`](https://github.com/Novolis-Platform/.github/blob/main/brand/logo-brand-transparent.svg).

The mark is built from locked vector points, straight-line `N` geometry, and circular arc-sector swirls. The generator lives in [`brand/generate-pixel-outlines.cs`](https://github.com/Novolis-Platform/.github/blob/main/brand/generate-pixel-outlines.cs) so the logo can be regenerated from the same coordinate source instead of being edited as opaque SVG path text.

---

## Open Source ❤️

Novolis is built openly, iteratively, and experimentally.

Ideas, feedback, prototypes, discussions, and weird experiments are welcome.

---

## Policies & docs 📚

| Resource | Link |
|----------|------|
| Contribution policy | [novolis-governance](https://github.com/Novolis-Platform/novolis-governance/blob/main/docs/contribution-policy.md) |
| Security policy | [SECURITY.md](https://github.com/Novolis-Platform/novolis-governance/blob/main/SECURITY.md) |
| CI & package publishing | [nuget-setup.md](https://github.com/Novolis-Platform/novolis-governance/blob/main/docs/nuget-setup.md) |
| Release & versioning | [release-policy.md](https://github.com/Novolis-Platform/novolis-governance/blob/main/docs/release-policy.md) |
| Reusable workflows | [novolis-workflows](https://github.com/Novolis-Platform/novolis-workflows) |
| Package registry | [novolis-registry](https://github.com/Novolis-Platform/novolis-registry) |
| Roadmap | [roadmap.md](https://github.com/Novolis-Platform/novolis-governance/blob/main/docs/roadmap.md) |
| Governance | [novolis-governance](https://github.com/Novolis-Platform/novolis-governance) |
| .NET repo template | [novolis-template-dotnet](https://github.com/Novolis-Platform/novolis-template-dotnet) |
