# Novolis Raylib — Package Ecosystem Specification

**Status:** Draft  
**Repo:** `novolis-raylib`  
**Packaging overview:** [raylib-package-ecosystem.md](../raylib-package-ecosystem.md)

---

## Goals

The package ecosystem shall:

* Provide an extremely low-friction onboarding experience.
* Support multiple developer archetypes simultaneously (beginner, hardcore game dev, enterprise senior .NET).
* Preserve direct access to native Raylib and **Raygui** APIs.
* Feel idiomatic to modern .NET developers.
* Avoid forcing architectural patterns.
* Scale from “first game” to “engine/tooling development.”
* Keep layers composable at the **repo** level while exposing **one primary install** for apps.
* Hide native interop complexity from most users.
* Preserve escape hatches for advanced users in **Runtime**.

---

## Naming

Follow Novolis org policy ([bootstrapping-organization.md](../bootstrapping-organization.md)):

| Kind | Pattern | Example |
|------|---------|---------|
| GitHub repo | `novolis-<domain>` | `novolis-raylib` |
| NuGet | `Novolis.Raylib[.<Facet>]` | `Novolis.Raylib.Runtime` |

**Do not** use a separate product brand (e.g. `RayKit`). **Do not** claim ownership of Raylib or Raygui. **Do not** use names that sound like Raylib forks.

All packages in this stack use the **`Novolis.Raylib.*`** prefix.

---

## What users install

| Audience | Package |
|----------|---------|
| Apps, games, tools | **`Novolis.Raylib`** |
| Test projects | **`Novolis.Raylib.Testing`** (depends **only** on `Novolis.Raylib`) |

```bash
dotnet add package Novolis.Raylib
```

That pulls in transitively every **product** package below. Users choose which **package to code against** (Game, Runtime, Hosting)—not which NuGets to add.

---

## NuGet packages (all real packages)

| Package | Role |
|---------|------|
| **`Novolis.Raylib.Native`** | raylib + raygui native binaries per RID; MSBuild targets |
| **`Novolis.Raylib.Abstractions`** | Contracts (frame renderer, shell runtime, hosting hooks) |
| **`Novolis.Raylib.Runtime`** | Codegen interop, façades, raygui load/bind, default shell, shared types |
| **`Novolis.Raylib.Hosting`** | `IHost`, DI, options, phased loops |
| **`Novolis.Raylib.Game`** | Jam / tutorial / low-ceremony entry |
| **`Novolis.Raylib`** | **Aggregate** — depends on **all** product packages above |
| **`Novolis.Raylib.Testing`** | Test harness |

`Novolis.Raylib.CodeGen` is **repo-only** (not published). Consumers never run codegen.

---

## Dependency graph

```text
Novolis.Raylib.CodeGen              (build only)

Novolis.Raylib.Native               (raylib + raygui binaries)

Novolis.Raylib.Abstractions  ──────► Native

Novolis.Raylib.Runtime       ──────► Abstractions, Native
     ▲                                (codegen emits into Runtime)
     │
     ├──────────────┬─────────────────┐
     │              │                 │
Novolis.Raylib.Hosting        Novolis.Raylib.Game
     │              │                 │
     └──────────────┴─────────────────┘
                    │
            Novolis.Raylib            (aggregate — user install)
                    ▲
                    │
            Novolis.Raylib.Testing    (→ Raylib only)
```

**Rules:**

* **Native** is the binary foundation; always **raylib + raygui** together.
* **Runtime** holds generated interop and façades; depends on **Abstractions** and **Native**.
* **Hosting** and **Game** depend on **Runtime** (not on the aggregate `Novolis.Raylib` project).
* **`Novolis.Raylib`** depends on **Native**, **Abstractions**, **Runtime**, **Hosting**, **Game**.
* **Testing** depends **only** on **`Novolis.Raylib`**.
* Lower layers never reference Hosting, Game, or Testing.

---

## Aggregate package — `Novolis.Raylib`

Primary user-facing package. Recommended install for nearly all users.

```bash
dotnet add package Novolis.Raylib
```

**Purpose:**

* One dependency line for discovery and docs
* Transitive reference to every product package
* Unified versioning across the stack

**Does not replace** the other packages—they remain separate NuGet IDs versioned and referenced from the aggregate.

---

## `Novolis.Raylib.Native`

Lowest layer: **native runtime only**.

**Contains:**

* raylib native libraries per RID
* raygui shim (built against the same raylib major) per RID
* MSBuild targets to copy/load natives in consuming apps

**Does not contain:**

* Generated C# bindings (those live in **Runtime**)
* Hosting, game loop, or DI concepts

**Characteristics:**

```text
Transitive via Novolis.Raylib
Mechanical
raylib + raygui inseparable
No public C# API (or minimal)
```

**Target audience:** none directly—apps reference **`Novolis.Raylib`**. Maintainers and package authors may reference **Native** when extending the stack.

---

## `Novolis.Raylib.Abstractions`

Stable **contracts** shared by Runtime, Hosting, and Testing.

**Contains (illustrative):**

* Per-frame renderer interface
* Shell / window loop runtime interface
* Hooks for hosting adapters

**Depends on:** **Native**

**Characteristics:**

```text
Small surface
Version carefully
No interop codegen
No jam or IHost opinions
```

---

## `Novolis.Raylib.Runtime`

Managed **middle layer** and **hardcore developer home base**.

**Contains:**

* **Codegen output:** raylib + raygui interop (`Novolis.Raylib.Interop` namespace)
* Manifest-driven **façades** (windowing, rendering, input, time, audio, …)
* Raygui shim load/bind (with **Native** assets)
* Default **shell** implementing **Abstractions**
* Shared types (colors, vectors, rectangles, …)
* Optional Raygui-friendly helpers (same package; no separate Gui NuGet required for v1)

**Depends on:** **Abstractions**, **Native**

**Characteristics:**

```text
Thin interop
Predictable façades
Mechanical bindings
Complete enough to ship without Game or Hosting
Unsafe allowed at interop boundary
```

**Namespace examples:**

```csharp
using Novolis.Raylib.Interop;      // generated bindings
using Novolis.Raylib.Rendering;    // façades
using Novolis.Raylib.Shell;
```

**Example (façade + shell):**

```csharp
public sealed class DemoFrame : IRaylibFrameRenderer
{
    public void OnFrame(float dt, int w, int h)
    {
        Graphics.ClearBackground(Color.RayWhite);
        Graphics.DrawText("Hello", 12, 12, 20, Color.DarkGray);
    }
}

RaylibRuntimeShell.RunShellFrame("Demo", new DemoFrame());
```

**Example (interop escape hatch):**

```csharp
using Novolis.Raylib.Interop;

Graphics.BeginDrawing();  // façade preferred when available
// or direct Raylib6Native.* where façades are insufficient
Graphics.EndDrawing();
```

**Target audience:**

* Veteran / hardcore game developers
* Engine and graphics programmers
* Tool authors who want control without jam or enterprise ceremony
* Anyone who needs **everything** without referencing **Game** or **Hosting**

---

## `Novolis.Raylib.Game`

High-level, beginner-friendly API. **Sugar on Runtime.**

**Purpose:**

* Minimal-friction onboarding
* Tutorials and classrooms
* Jams and first prototypes

**Depends on:** **Runtime** (+ **Abstractions**, **Native** as needed)

**Primary API (illustrative):**

```csharp
RayGame.Run("Demo", 800, 600, game =>
{
    game.Draw(ctx =>
    {
        ctx.Text("Hello");
    });
});
```

**Characteristics:**

```text
Minimal setup
Few concepts
Single-file-friendly
Immediate feedback
Opinionated simplicity
```

**Target audience:**

* First-time game developers
* Kids and hobbyists learning games
* Jam projects
* Quick prototypes

**Not** a separate install story—beginners still add **`Novolis.Raylib`** and use types from **`Novolis.Raylib.Game`**.

---

## `Novolis.Raylib.Hosting`

Modern .NET **hosting** integration. **Sugar on Runtime.**

**Purpose:**

* Structured applications
* Team and enterprise-style solutions
* Testability via DI
* Lifecycle and configuration

**Depends on:** **Runtime** (+ **Abstractions**, **Native** as needed)

**Primary API (illustrative):**

```csharp
var builder = RaylibHost.CreateApplicationBuilder(args);
// register systems, options, logging
var app = builder.Build();
await app.RunAsync();
```

**Characteristics:**

```text
IHost-based
DI-enabled
Options pattern
Logging integration
Lifecycle-aware
Testable
```

**Supports loop models:**

```text
RenderLoop   — Input → FixedUpdate → Update → Render
EventLoop    — Poll → Dispatch → Render if invalidated
```

**Target audience:**

* Senior .NET developers
* Enterprise developers entering games or realtime tools
* Simulation and tooling teams
* Professional tool developers

---

## `Novolis.Raylib.Testing`

Testing and simulation helpers. **Separate NuGet**; **only** references **`Novolis.Raylib`**.

**Contains:**

* Headless / offscreen loop drivers
* Fake input and clocks where useful
* Deterministic frame stepping
* CI opt-in for native test runs
* Runner-specific adapters (e.g. TUnit) **only** if generic APIs are insufficient

**Purpose:**

* Unit and integration testing
* Headless CI

```bash
dotnet add package Novolis.Raylib.Testing
```

---

## API layering and progressive disclosure

Same install (`Novolis.Raylib`); increasing sophistication by **which package you code in**:

| Level | Package / API | Illustrative entry |
|-------|---------------|-------------------|
| Beginner | `Novolis.Raylib.Game` | `RayGame.Run(...)` |
| Hardcore / engine | `Novolis.Raylib.Runtime` | Shell + façades + `Novolis.Raylib.Interop` |
| Enterprise senior | `Novolis.Raylib.Hosting` | `RaylibHost.CreateApplicationBuilder(...)` |

No rewrite required when moving between levels—**Runtime** remains available under **Game** and **Hosting**.

---

## Loop models

### RenderLoop

Frame-driven realtime simulation.

**Suitable for:** games, physics, animation, realtime rendering.

**Lifecycle:**

```text
Input
FixedUpdate
Update
Render
```

Implemented primarily in **Hosting**; **Runtime** shell provides a simpler single-callback loop for direct use.

### EventLoop

Invalidation / event-driven rendering.

**Suitable for:** editors, tools, launchers, turn-based games, utilities.

**Lifecycle:**

```text
Poll
Dispatch events
Render if invalidated
```

---

## System contracts (`Novolis.Raylib.Hosting`)

Hosting may define phased systems invoked from the host loop:

```csharp
IStartupSystem
IFixedUpdateSystem
IUpdateSystem
IRenderSystem
IShutdownSystem
```

Contracts for frames and shell live in **`Novolis.Raylib.Abstractions`**; implementations in **Runtime** and **Hosting**.

---

## Developer archetypes

| Archetype | Package | Experience goal |
|-----------|---------|-----------------|
| **Beginner / first game** | `Novolis.Raylib.Game` | Immediate gratification; visible results in minutes |
| **Hardcore / engine dev** | `Novolis.Raylib.Runtime` | No unnecessary abstraction; direct control; full toolkit |
| **Enterprise senior .NET** | `Novolis.Raylib.Hosting` | Familiar host, DI, configuration, logging |
| **Library / adapter author** | `Novolis.Raylib.Abstractions` (+ lower layers) | Stable contracts without pulling Game |
| **Test author** | `Novolis.Raylib.Testing` | Deterministic, headless, CI-friendly |

---

## Build pipeline (maintainers)

```text
manifests + native sources
        │
        ├── build → Novolis.Raylib.Native
        │
        └── codegen → Novolis.Raylib.Runtime
                    │
                    compile Abstractions, Runtime, Hosting, Game
                    pack all product NuGets + Novolis.Raylib + Testing
```

Raygui is generated and loaded as part of **Runtime**, with binaries from **Native**.

---

## Architectural rules

### Required

* **raylib + raygui** always bundled in **Native**
* Codegen at **library build** only; output in **Runtime**
* **Many packages, one graph**; apps install **`Novolis.Raylib`**
* **Runtime** is complete for hardcore devs without Game/Hosting
* Native escape hatch via **`Novolis.Raylib.Interop`**
* Predictable ownership and lifetime
* Minimal hidden behavior
* All layers composable; no forced ECS, scene graph, asset pipeline, or editor

### Forbidden

* Publishing Game or Hosting as substitutes for **`Novolis.Raylib`**
* Optional raygui-less **Native**
* Codegen in **consumer** projects
* Mandatory dependency injection for a hello-world
* Reflection-heavy startup requirements
* Hidden threading models
* Mandatory retained-mode UI hierarchies
* Mandatory inheritance-based gameplay architecture
* Documenting direct app references to **Native** / **Runtime** in quickstarts (use **`Novolis.Raylib`**)

---

## Primary design principle

> The stack scales from “my first game” (**Game**) to “I run the engine myself” (**Runtime**) to “this is a proper .NET app” (**Hosting**) without abandoning earlier mental models—**one install (`Novolis.Raylib`)**, **many real packages**, **Runtime** at the center.

---

## Related docs

* [raylib-package-ecosystem.md](../raylib-package-ecosystem.md) — packaging and dependency rules
* [bootstrapping-organization.md](../bootstrapping-organization.md)
* [profile/README.md](../../profile/README.md)
