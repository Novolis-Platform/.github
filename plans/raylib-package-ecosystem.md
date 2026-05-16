# Novolis Raylib Package Ecosystem Specification

**Status:** Draft  
**Repo:** `novolis-raylib`  
**Aligns with:** [bootstrapping-organization.md](bootstrapping-organization.md)

---

## Summary

The Raylib stack is **multiple NuGet packages** with a fixed dependency graph. **`Novolis.Raylib`** is the package users add; it **depends on every other product package** and pulls them in transitively.

**`Novolis.Raylib.Testing`** is the only other consumer-facing package. It depends **only** on **`Novolis.Raylib`**.

**`Novolis.Raylib.Runtime`** is the middle layer: generated interop, façades, raygui load/bind, default shell, shared types. It depends on **`Novolis.Raylib.Abstractions`**. **`Novolis.Raylib.Hosting`** and **`Novolis.Raylib.Game`** depend on **Runtime**.

Three packages sit on **Runtime** for different audiences — same install (`Novolis.Raylib`), different entry points in code:

| Package | Who it is for |
|---------|----------------|
| **`Novolis.Raylib.Game`** | First games, jams, tutorials — lowest ceremony, fastest “something on screen” |
| **`Novolis.Raylib.Runtime`** | Experienced game/graphics developers — interop, façades, shell; **everything they need** without Game or Hosting sugar |
| **`Novolis.Raylib.Hosting`** | Senior .NET / enterprise-style apps — `IHost`, DI, options, phased systems |

---

## NuGet packages (all real packages)

| Package | Role |
|---------|------|
| **`Novolis.Raylib.Native`** | raylib + raygui natives per RID; MSBuild targets |
| **`Novolis.Raylib.Abstractions`** | Contracts (frame renderer, shell runtime, …) |
| **`Novolis.Raylib.Runtime`** | Codegen interop, façades, raygui bind/load, default shell — **hardcore / engine path** |
| **`Novolis.Raylib.Hosting`** | `IHost`, DI, options, phased loops — **enterprise senior path** |
| **`Novolis.Raylib.Game`** | `Run(…)` jam API — **beginner / first-game path** |
| **`Novolis.Raylib`** | **User-facing aggregate** — depends on **all** of the above |
| **`Novolis.Raylib.Testing`** | Test harness — depends **only** on `Novolis.Raylib` |

`Novolis.Raylib.CodeGen` is **repo-only** (not published).

---

## Why the middle package is named **Runtime**

| Candidate | Verdict |
|-----------|---------|
| **`Runtime`** ✓ | Managed layer that *runs* raylib on .NET: interop, façades, shell, types. Sits above **Native**, below **Hosting** / **Game**. |
| `Interop` | Too narrow — same name as a namespace inside Runtime; sounds like P/Invoke only. |
| `Core` | Rejected — [governance](bootstrapping-organization.md) discourages `core` in names. |
| `Bindings` | Rejected — describes codegen output only, not shell or façades. |
| `Platform` | Reasonable but vague next to org brand “platform”; **Runtime** is clearer in a dependency diagram. |

---

## What users install

```bash
# apps, games, tools
dotnet add package Novolis.Raylib

# test projects only
dotnet add package Novolis.Raylib.Testing
```

`Novolis.Raylib` brings in transitively: **Native**, **Abstractions**, **Runtime**, **Hosting**, **Game**.

Advanced authors may reference a lower package directly (e.g. **Abstractions** only for a adapter library).

---

## Dependency graph (required)

```text
Novolis.Raylib.CodeGen                 (build only — not on NuGet)

Novolis.Raylib.Native                (binaries + raygui shim)

Novolis.Raylib.Abstractions  ───────► Native

Novolis.Raylib.Runtime       ───────► Abstractions, Native
     ▲                                 │
     │                                 │ codegen emits into Runtime
     ├─────────────┬────────────────────┘
     │             │
Novolis.Raylib.Hosting  ────────────► Runtime, Abstractions, Native
Novolis.Raylib.Game     ────────────► Runtime, Abstractions, Native

Novolis.Raylib ─────────────────────► Native
                                       Abstractions
                                       Runtime
                                       Hosting
                                       Game

Novolis.Raylib.Testing ─────────────► Novolis.Raylib   (only this edge)
```

**In words:**

1. **Native** — foundation.
2. **Abstractions** — depends on **Native**.
3. **Runtime** — depends on **Abstractions** + **Native**; hosts codegen output.
4. **Hosting** and **Game** — depend on **Runtime** (not on `Novolis.Raylib`).
5. **`Novolis.Raylib`** — depends on **Native**, **Abstractions**, **Runtime**, **Hosting**, **Game**.
6. **Testing** — depends **only** on **`Novolis.Raylib`**.

---

## `Novolis.Raylib.Runtime`

**Position:** between **Native** and **`Novolis.Raylib`** (and under **Hosting** / **Game**).

**Depends on:** `Novolis.Raylib.Abstractions`, `Novolis.Raylib.Native`

**Depended on by:** `Novolis.Raylib.Hosting`, `Novolis.Raylib.Game`, `Novolis.Raylib`

**Audience:** veteran and “hardcore” game developers — engine programmers, graphics coders, anyone who wants **direct control** without jam APIs or enterprise hosting ceremony.

**Function:**

* **Codegen** at library build → raylib + raygui interop and manifest-driven façades
* Load/bind raygui shim with **Native** assets
* Implement **Abstractions** (default shell / frame loop)
* Shared value types (colors, vectors, rectangles, …)
* **Complete toolkit** for building games/tools at this layer: raw interop escape hatch + façades + shell — no requirement to reference **Game** or **Hosting**

**Typical namespaces** (implementation detail):

* `Novolis.Raylib.Interop` — generated bindings
* `Novolis.Raylib.Rendering`, `.Windowing`, `.Shell`, … — façades and glue

---

## Developer paths (same install, different packages in code)

Everyone adds **`Novolis.Raylib`** once. Which **package** you primarily code against is a choice of style, not a second NuGet install.

| Path | Package to work in | Experience |
|------|-------------------|------------|
| **First game / jam / teaching** | `Novolis.Raylib.Game` | “Run a window and draw” in minutes; minimal concepts |
| **Hardcore / engine / graphics** | `Novolis.Raylib.Runtime` | Façades, shell, `Novolis.Raylib.Interop` — full control, no forced DI or jam wrappers |
| **Enterprise / senior .NET** | `Novolis.Raylib.Hosting` | Familiar `IHost`, DI, configuration, logging, update/render phases |

**Game** and **Hosting** are opinionated **sugar on top of Runtime** — they do not replace it and do not hide it from those who need it. A hardcore developer can ignore **Game** and **Hosting** entirely and live in **Runtime**.

---

## Per-package function

### `Novolis.Raylib.Native`

* raylib + raygui per RID; MSBuild targets.
* Raygui is **first-class** — always paired with raylib.

### `Novolis.Raylib.Abstractions`

* Stable interfaces for frames, shell, hosting adapters.
* **Own NuGet package.**

### `Novolis.Raylib.Runtime`

* Mechanical + ergonomic layer over **Native**; implements **Abstractions**.
* **Own NuGet package** — the **hardcore developer home base**.
* Everything needed to ship without touching **Game** or **Hosting**.

### `Novolis.Raylib.Hosting`

* Generic host, DI, options, logging, phased loops.
* **Own NuGet package** → depends on **Runtime**.
* **Enterprise senior .NET** path — structured apps, teams, testability.

### `Novolis.Raylib.Game`

* Low-ceremony `Run(title, w, h, …)` (and similar) entry APIs.
* **Own NuGet package** → depends on **Runtime**.
* **Beginner / jam / first-game** path — a kid’s first game, a weekend jam, a classroom exercise.

### `Novolis.Raylib`

* **Aggregate** — project-references every product package above.
* **Own NuGet package** — the one-line install for apps.

### `Novolis.Raylib.Testing`

* Headless/offscreen tests, doubles, CI gates.
* **Only** references **`Novolis.Raylib`** in docs and examples.

---

## Build pipeline (maintainers)

```text
manifests + native sources
        │
        ├── build → Novolis.Raylib.Native
        │
        └── codegen (Novolis.Raylib.CodeGen) → emit into Novolis.Raylib.Runtime
                    │
                    compile Abstractions, Runtime, Hosting, Game
                    │
                    pack all NuGets + Novolis.Raylib + Testing
```

---

## Publishing

Separate publishable IDs (same repo, aligned versions):

```text
Novolis.Raylib.Native
Novolis.Raylib.Abstractions
Novolis.Raylib.Runtime
Novolis.Raylib.Hosting
Novolis.Raylib.Game
Novolis.Raylib
Novolis.Raylib.Testing
```

---

## Open decisions

- [ ] Minimal vs explicit Native refs on Hosting / Game projects
- [ ] Public vs `internal` types in `Novolis.Raylib.Interop`
- [ ] TUnit-specific helpers in **Testing**

---

## Primary design principle

> **Many packages, one graph; one install.** **Runtime** is the managed core — where hardcore developers live (interop, façades, shell). **Game** is the beginner on-ramp. **Hosting** is the enterprise senior on-ramp. All three sit on **Runtime**; **`Novolis.Raylib` depends on all product packages.** **`Novolis.Raylib.Testing` depends only on `Novolis.Raylib`.**

---

## Related docs

* [raylib/raylib-ecosystem-specs.md](raylib/raylib-ecosystem-specs.md) — detailed API, archetypes, loops, rules
* [bootstrapping-organization.md](bootstrapping-organization.md)
* [profile/README.md](../profile/README.md)
