# Novolis Logo Specification

**Status:** Implemented (v1)  
**Format assumption:** SVG (primary master); raster exports derived from SVG only  
**Scope:** Organization mark, favicon, and social/avatar variants — not per-package icons

---

## 1. Purpose

The Novolis logo must read as **platform infrastructure for modern .NET tooling** — calm, structured, and professional — not as a consumer app, game studio, crypto project, or hype-driven startup.

It should work when spoken aloud in meetings (“we use Novolis.Hosting”) and when shown at 16×16 px beside `Novolis.Raylib` in a README.

---

## 2. Name Semantics (Design Inputs)

Use these meanings to guide concept exploration. The mark does **not** need to illustrate all of them; pick one or two and execute with restraint.

| Root | Meaning | Visual direction (optional) |
|------|---------|------------------------------|
| **Novo** | renewal, iteration, evolution, modern systems | forward motion, layered steps, a single refined stroke replacing a rough one, subtle “new layer” geometry |
| **-olis** | structure, calm, conversational naturalness | grid-aligned forms, balanced negative space, rounded-but-not-bubbly corners |
| **Novolis (whole)** | ecosystem, modularity, progressive complexity | composable units, repeated module with variation, parent/child shapes that nest cleanly |

**Tone words:** modern (not trendy), technical (not cold), platform-oriented (not product-campaign), professional (not corporate), memorable (not abbreviation-dependent).

**Anti-tone (from naming philosophy):** startup buzzword energy, crypto, fantasy, “next-gen ultra hyper” framework marketing.

---

## 3. Concept Directions (Choose One Primary)

Exploration should produce **3–5 distinct concepts**, each viable as a single-color mark. One concept is selected as primary; others may inform secondary patterns only if explicitly approved.

### A. Monogram — `N`

A geometric **N** built from straight segments and one intentional curve or notch — suggesting structure (`-olis`) and a forward step (`novo`). Must remain legible at favicon size without becoming “Nike swoosh” or a generic tech N.

### B. Modular mark — composable blocks

Two to four simple rectangles or rounded rects that **snap to a shared grid**, implying packages (`Novolis.*`) without depicting code, NuGet, or .NET logos. One block may be offset or highlighted to suggest iteration/evolution.

### C. Layer / stack — progressive complexity

Two or three horizontal or diagonal layers, slightly offset, implying stacking capabilities and “low ceremony → escape hatches when needed.” Avoid literal server-rack or cloud-stack clichés.

### D. Path / conduit — calm flow

A single continuous stroke (open or closed) suggesting a channel or pipeline — realtime, transports, messaging — **without** looking like a network diagram, circuit board, or plumbing icon.

### E. Wordmark-adjacent symbol

A compact symbol that pairs with the word **Novolis** in horizontal lockups only; the symbol alone must still work for avatars. Do not rely on the full wordmark inside the favicon.

**Rejected concept families (do not explore):** mascots, shields, rockets, coins, wizards, game controllers, hexagonal “Web3” badges, gradient orbs, AI sparkles, .NET purple swatches as the hero element.

---

## 4. Visual System

### 4.1 Geometry

- **Grid:** Design on a square artboard with a **24×24** or **32×32** logical unit grid; key anchors on integer coordinates.
- **Stroke vs fill:** Prefer **filled shapes** or **uniform strokes** (not mixed hairline + heavy stroke in the same mark).
- **Corner radius:** If rounded, use **one** radius token (e.g. 2u or 3u on a 24u grid) — no arbitrary per-corner radii.
- **Optical balance:** Center the mark in the viewBox; leave **≥12.5%** clear padding on all sides (safe area) for circular masks (GitHub org avatar).
- **Symmetry:** Bilateral symmetry is allowed but not required; if asymmetric, the mark must not look “accidentally cropped.”

### 4.2 Color

**Primary delivery:** single-color SVG (`currentColor` or explicit fill) for maximum reuse.

| Role | Guidance |
|------|----------|
| **Default** | Near-black `#1a1a1a` on light backgrounds; near-white `#f5f5f5` on dark |
| **Accent (optional)** | One cool neutral or blue-gray (e.g. `#3d5a73` – `#4a6fa5` range) — not neon, not purple-heavy “AI” gradient |
| **Dark mode** | Same geometry; invert or swap fill — no separate “glow” version |

**Gradients:** Avoid in the master mark. If a marketing variant is ever needed, it is a **derivative file**, not the canonical logo.

### 4.3 Typography (lockups only)

- Wordmark: **Novolis** — sentence case **N** only; never **NOVOLIS**, never **novolis** in the logo lockup.
- Typeface: neutral grotesque or humanist sans (e.g. Inter, IBM Plex Sans, Source Sans 3 class) — no sci-fi, no stencil, no slab “enterprise 2005.”
- Letter-spacing: default or slightly tight; no exaggerated tracking.
- The symbol and wordmark align on a shared **cap-height or x-height** baseline in horizontal lockups.

---

## 5. SVG Technical Requirements

### 5.1 File structure

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="Novolis">
  <!-- paths only; no embedded raster -->
</svg>
```

- **viewBox:** Square; canonical `0 0 24 24` (favicon) and `0 0 32 32` or `0 0 64 64` for large master — scale via viewBox, not width/height hacks in the master file.
- **Paths:** Prefer `<path>`; minimize `<transform>` nesting; no `<clipPath>` unless required for export masks.
- **IDs/classes:** Prefix with `novolis-` if needed; strip unused defs on export.
- **No** embedded fonts, images, filters (`feGaussianBlur`, drop shadows), or `<foreignObject>`.
- **Accessibility:** `role="img"` and `aria-label="Novolis"` on standalone marks; decorative instances use `aria-hidden="true"`.

### 5.2 Optimization

- Hand-tuned or SVGO with conservative plugins; verify **16×16** preview after optimization.
- Target **≤ 2 KB** for favicon-grade SVG when reasonable; hard cap **≤ 8 KB** for master without metadata bloat.

### 5.3 Deliverables (when implemented)

| Asset | viewBox | Notes |
|-------|---------|--------|
| `logo-mark.svg` | 24×24 | Symbol only, `currentColor` |
| `logo-mark-mono-dark.svg` | 24×24 | Explicit light fill for dark UI |
| `logo-lockup-horizontal.svg` | proportional | Symbol + “Novolis” |
| `favicon.svg` | 24×24 | Same as mark; test in browser tab |
| `social-512.png` | — | Exported from SVG @512×512, transparent PNG |

---

## 6. Usage Contexts (Must Pass)

| Context | Size | Requirement |
|---------|------|-------------|
| GitHub org avatar | 420×420 displayed, often circular crop | Readable silhouette; no fine interior detail |
| Favicon | 16×16, 32×32 | Recognizable; no text inside mark |
| README header | ~32–48 px height | Clear beside `# Novolis` |
| NuGet / package icon | 64×64 | Works on white and light gray `#f6f8fa` |
| Terminal / CLI splash | optional | Monochrome; no animation in canonical SVG |
| Slide decks | large | No redesign at scale — same paths |

---

## 7. Explicit Don’ts

### 7.1 Brand & meaning

- **Don’t** suggest cryptocurrency, blockchain, tokens, or “coin” metaphors (circles with slashes, pickaxes, moons, diamonds).
- **Don’t** suggest fantasy RPG, anime, or spellbook aesthetics (runes, crystals, dragons, swords).
- **Don’t** use startup clichés: rockets, lightning “disruption,” upward-only chart arrows, “infinite” loops implying hypergrowth.
- **Don’t** imitate or riff on **Microsoft .NET**, **NuGet**, **GitHub**, or **Raylib** official logos — Novolis is adjacent, not a fork brand.
- **Don’t** imply a single product (one game, one app); the mark is **platform/ecosystem**, not a title screen.

### 7.2 Visual style

- **Don’t** use rainbow gradients, holographic meshes, glassmorphism, or neon glow as the default mark.
- **Don’t** use stock “tech” tropes: globes with meridians, generic nodes-and-edges graphs, brain icons, robot faces, sparkles for “AI.”
- **Don’t** use 3D extrusion, long shadows, or skeuomorphic metal/gloss in the master SVG.
- **Don’t** use more than **two** distinct hues in the canonical logo (monochrome preferred).
- **Don’t** use outlines so thin they disappear at 16×16 (minimum stroke **1.5u** on 24u grid if stroke-based).
- **Don’t** rely on color alone to distinguish parts (must read in grayscale).

### 7.3 Typography & naming

- **Don’t** set the wordmark in a display font, script, or monospace “code” font as the **logo** (monospace is fine in docs, not in the mark).
- **Don’t** add taglines inside the logo file (“Realtime .NET”, “The future of…”) — taglines are separate layout.
- **Don’t** abbreviate to **NVLS**, **NPL**, or **N**-in-a-circle as the **primary** brand without the full name in lockups for org properties.
- **Don’t** include `.Platform`, `.NET`, or package names (`Raylib`, `Hosting`) in the org mark.

### 7.4 SVG & files

- **Don’t** ship Photoshop-exported SVG with thousands of points or embedded bitmaps.
- **Don’t** use CSS animations in the canonical org avatar or favicon SVG.
- **Don’t** depend on system fonts in SVG (`<text>`) for the master mark — outlines paths for the symbol; wordmark lockups may use outlined text or separate WOFF with license noted.
- **Don’t** use non-square viewBoxes for the primary mark (breaks favicon and avatar pipelines).

### 7.5 Legal & community

- **Don’t** use third-party IP (game characters, corporate marks, Font Awesome glyphs copied verbatim).
- **Don’t** produce marks that could be confused with **Novell**, **Nvidia**, **Nokia**, or other “Nov-” brands at a glance — review at small size.

---

## 8. Evaluation Checklist

Before approving a concept:

1. **16×16 test:** Silhouette recognizable in 3 seconds?
2. **Grayscale test:** Parts still distinct?
3. **Avatar crop:** Circle mask loses no critical feature?
4. **Say-aloud test:** Still feels like infrastructure when paired with `Novolis.Hosting`?
5. **README test:** Works at 32 px next to plain markdown heading?
6. **Anti-buzzword test:** Would this look wrong on a bank intranet and a game dev blog? (Should feel acceptable on both.)
7. **SVG hygiene:** Valid XML, no raster, under size budget?

**Scoring:** Pass all seven; any fail → revise or discard concept.

---

## 9. Optional Secondary Patterns (Not Logo)

These may inspire **docs diagrams** or **repo topic colors** but must **not** appear in the org mark without explicit approval:

- Subtle grid or dot matrix (developer tooling)
- Single accent stripe (package “channel” metaphor)

Keep secondary patterns out of favicon and org avatar files.

---

## 10. Reference (Non-binding)

**Sounds like:** structured conversation, calm engineering, modular packages.  
**Does not sound like:** crypto exchange, anime MMO, “Series A” pitch deck, fantasy spellbook.

**Related docs:** [profile/README.md](../profile/README.md) — naming philosophy and ecosystem positioning.

---

## 11. Open Decisions (Resolve Before Final Art)

- [x] Primary concept **C** (layer / stack) — see [`brand/`](../brand/)
- [x] Monochrome-only (no accent hex in v1)
- [x] Full v1 deliverables: mark, mono-dark, favicon, horizontal lockup, `social-512.png`
- [ ] Trademark clearance search for nearest “Nov-” marks in software (manual, pre-public launch)
