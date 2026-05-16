# Package Ecosystem Specification

## Goals

The package ecosystem shall:

* Provide an extremely low-friction onboarding experience.
* Support multiple developer archetypes simultaneously.
* Preserve direct access to native Raylib APIs.
* Feel idiomatic to modern .NET developers.
* Avoid forcing architectural patterns.
* Scale from “first game” to “engine/tooling development.”
* Keep layers optional and composable.
* Hide native interop complexity from most users.
* Preserve escape hatches for advanced users.

---

# Naming

Avoid personal branding.

Avoid claiming ownership of the Raylib name itself.

Avoid names that sound like forks of Raylib.

Recommended:

## Primary Recommendation

# `RayKit`

Simple.

Memorable.

Feels .NET-friendly.

Does not conflict semantically with Raylib.

Examples:

```text
RayKit
RayKit.Native
RayKit.Hosting
RayKit.Game
RayKit.Gui
RayKit.Testing
```

This is probably the strongest option.

---

## Other Strong Candidates

| Name         | Notes                                    |
| ------------ | ---------------------------------------- |
| `RayKit`     | strongest overall                        |
| `RayFrame`   | slightly engine-like                     |
| `RayCore`    | sounds low-level                         |
| `RayWorks`   | tooling vibe                             |
| `RayLoop`    | too loop-focused                         |
| `RaySharp`   | too close to older C# naming conventions |
| `RayForge`   | more engine/editor vibe                  |
| `RayStack`   | modern infra vibe                        |
| `RayRuntime` | too technical                            |
| `RayHost`    | hosting-only implication                 |

---

# Package Structure

## Meta Package

# `RayKit`

Primary user-facing package.

Recommended install target for nearly all users.

```bash
dotnet add package RayKit
```

Includes:

```text
RayKit.Native
RayKit.Game
RayKit.Hosting
RayKit.Gui
```

Purpose:

* Beginner onboarding
* Most production games/tools
* Simplified discovery
* Unified documentation/examples

---

# Core Packages

## `RayKit.Native`

Lowest-level package.

Contains:

* Source-generated native bindings
* Native runtime assets
* Raw Raylib bindings
* Raw RayGui bindings
* Unsafe/native APIs
* Zero hosting abstractions
* Zero lifecycle abstractions

Characteristics:

```text
Thin
Predictable
Mechanical
Complete
Unsafe allowed
```

Namespace:

```csharp
using RayKit.Native;
```

Example:

```csharp
RaylibNative.InitWindow(...);
RaylibNative.BeginDrawing();
```

Target audience:

* Engine developers
* Graphics programmers
* Advanced users
* Low-level debugging
* Native experimentation

---

## `RayKit.Game`

High-level beginner-friendly API.

Purpose:

* Minimal-friction onboarding
* Tutorials
* Educational usage
* Rapid prototyping

Primary API:

```csharp
RayGame.Run(...);
```

Characteristics:

```text
Minimal setup
Few concepts
Single-file-friendly
Immediate feedback
Opinionated simplicity
```

Example:

```csharp
RayGame.Run("Demo", 800, 600, game =>
{
    game.Draw(ctx =>
    {
        ctx.Text("Hello");
    });
});
```

Target audience:

* Children
* Hobbyists
* First-time game developers
* Jam projects
* Quick prototypes

---

## `RayKit.Hosting`

Modern .NET hosting integration.

Purpose:

* Structured applications
* Team development
* Large projects
* Testability
* Dependency injection
* Lifecycle management

Primary API:

```csharp
RayHost.CreateApplicationBuilder(args);
```

Characteristics:

```text
IHost-based
DI-enabled
Options pattern
Logging integration
Lifecycle-aware
Testable
```

Supports:

```text
RenderLoop
EventLoop
FixedUpdate
Update
Render
Startup/Shutdown phases
```

Target audience:

* Professional .NET developers
* Tool developers
* Enterprise developers entering games
* Simulation developers

---

## `RayKit.Gui`

Optional GUI helpers and wrappers.

Contains:

* Friendly RayGui APIs
* Optional retained-style helpers
* GUI composition helpers

Characteristics:

```text
Optional
Non-invasive
No hosting dependency
```

Namespaces:

```csharp
using RayKit.Gui;
```

---

## `RayKit.Testing`

Testing and simulation helpers.

Contains:

* Fake input
* Fake clocks
* Headless runtime helpers
* Snapshot helpers
* Deterministic timing
* Test loop drivers

Purpose:

* Unit testing
* Integration testing
* Headless CI

---

# API Layering

Dependency direction:

```text
RayKit.Native
    ↑
RayKit
    ↑
RayKit.Game
    ↑
RayKit.Hosting

RayKit.Gui
    ↑
RayKit
```

Rules:

* Higher layers may depend on lower layers.
* Lower layers must never depend on hosting or game abstractions.
* Hosting must remain optional.
* Native APIs must remain directly accessible.

---

# Public API Philosophy

## Progressive Disclosure

The framework shall support increasing sophistication without requiring rewrites.

### Beginner

```csharp
RayGame.Run(...);
```

### Intermediate

```csharp
using var window = RayWindow.Open(...);
```

### Structured

```csharp
RayHost.CreateApplicationBuilder(...);
```

### Low-level

```csharp
RaylibNative.BeginDrawing();
```

---

# Loop Models

Supported loop models:

## RenderLoop

Frame-driven realtime simulation.

Suitable for:

* Games
* Physics
* Animation
* Realtime rendering

Lifecycle:

```text
Input
FixedUpdate
Update
Render
```

---

## EventLoop

Invalidation/event-driven rendering.

Suitable for:

* Editors
* Tools
* Launchers
* Turn-based games
* Utility apps

Lifecycle:

```text
Poll
Dispatch events
Render if invalidated
```

---

# System Contracts

## Startup

```csharp
IStartupSystem
```

## Fixed Update

```csharp
IFixedUpdateSystem
```

## Variable Update

```csharp
IUpdateSystem
```

## Render

```csharp
IRenderSystem
```

## Shutdown

```csharp
IShutdownSystem
```

---

# Developer Archetype Evaluation

## Beginner

Preferred entry:

```csharp
RayGame.Run(...)
```

Experience goal:

```text
Immediate gratification
Minimal concepts
Visible results in minutes
```

---

## Junior Developer

Preferred entry:

```csharp
RayHost + systems
```

Experience goal:

```text
Learn modern .NET structure naturally
```

---

## Senior .NET Developer

Preferred entry:

```csharp
RayKit.Hosting
```

Experience goal:

```text
Familiar host/lifecycle/configuration patterns
```

---

## Veteran Engine Developer

Preferred entry:

```csharp
RayWindow
RaylibNative
```

Experience goal:

```text
No unnecessary abstraction
Fast experimentation
Direct control
```

---

# Architectural Rules

## Required

* All layers optional
* No forced ECS
* No forced scene graph
* No forced asset pipeline
* No forced editor
* Native escape hatch always available
* Predictable ownership/lifetime
* Minimal hidden behavior

---

## Forbidden

* Mandatory dependency injection
* Reflection-heavy startup requirements
* Hidden threading models
* Magic code generation in user projects
* Mandatory retained-mode object hierarchies
* Mandatory inheritance-based gameplay architecture

---

# Primary Design Principle

> The framework shall scale from “my first game” to “I am writing an engine subsystem” without forcing users to abandon earlier code or mental models.
