# Vertical Layout & 3-Wave Levels — Design

Date: 2026-07-21

## Problem

On a narrow (portrait) phone screen the game looks bad: the enemy grid (11×5 = 55
aliens) and 4 shields are crammed together and hard to hit with a finger.

Root cause of the poor layout: **two conflicting logical coordinate systems.**
- `GameEngine` authors all gameplay entities in a portrait space of `W = 400`,
  `H = 780`.
- `Renderer` defines `gameW = 800`, `gameH = 600` (landscape 4:3) and its Phase-3
  letterbox transform scales/offsets game content using those dimensions. All HUD
  and full-screen menus (splash, game over, level banner) are also authored in
  800×600.

Because gameplay verts (0..400, 0..780) are transformed as if they lived in an
800×600 space, gameplay is squished into roughly the left half horizontally and
spills below the visible letterbox vertically.

## Goals

1. Make the game a proper vertical (portrait) experience that fills the narrow
   screen.
2. Fewer, larger, more finger-friendly enemies and barricades.
3. Each level is made of **3 waves**, each with a distinct dynamic.

## Design

### 1. Unify coordinates to portrait

- Change `Renderer.gameW` / `Renderer.gameH` from `800/600` to `400/780` to match
  the engine's authored space.
- The HUD, splash, game-over, and level-banner draw code already positions content
  relative to `gameW/gameH` (e.g. `H*0.12`, `W/2`), so it reflows to portrait
  automatically.
- Retune the handful of landscape-specific absolute values (splash title size,
  HUD margins/spacing, high-score column x-offsets, alien-demo row spacing) so they
  fit the 400-wide field without overlapping.

### 2. Enemy formation & waves

- Formation: **4 columns × 3 rows = 12 aliens**, larger sprites (~40 px) with
  generous spacing, centered in the 400-wide field.
- `alienCols = 4`, `alienRows = 3`, `alienW = 40`, `alienH = 28` (approx; tuned to
  fit with comfortable gaps and side margins).
- A **level consists of 3 waves.** Track `wave` (1…3) in `GameEngine`.
  - Clearing a wave (all aliens dead) with `wave < 3`: show a brief "WAVE n" banner,
    then set up the next wave's aliens (shields and player state persist).
  - Clearing wave 3: advance `level`, reset `wave = 1`, rebuild shields, show the
    existing "LEVEL n" banner.
- Wave dynamics:
  - **Wave 1 – Classic:** standard side-to-side march that descends on edge hits,
    moderate fire rate. (Current behavior.)
  - **Wave 2 – Swarm:** faster and more erratic horizontal motion; individual
    aliens periodically break formation and dive-bomb toward the player's current x
    position, then are removed when they leave the bottom of the screen.
  - **Wave 3 – Onslaught:** high fire rate; aliens take **2 hits** to destroy (first
    hit applies a visible damage tint); a UFO pass is guaranteed during the wave.

### 3. Shields

- **3 medium shields**, larger pixel footprint than today, evenly spaced across the
  width.
- Shield damage **persists across all 3 waves** of a level. Shields are fully
  rebuilt only when a new level begins.
- Implementation: split `setupLevel()` so alien/wave setup is separate from shield
  setup. Shields are (re)built on level start; wave transitions rebuild only aliens.

### 4. Scoring / HUD

- HUD shows a small **"WAVE n/3"** indicator alongside the level readout.
- The wave transition reuses the level-banner rendering style (e.g. "WAVE 2").
- Alien point values and power-up drops are unchanged. Wave 3's 2-hit aliens still
  award points once destroyed.

## Wave / phase flow

`GamePhase` gains a `waveTransition` case (or reuses `levelTransition` with a flag).
Recommended: reuse `levelTransition` with a boolean/enum indicating whether the
transition advances a wave or a level, so the banner text and setup differ but the
timing/particle burst logic is shared.

State on clearing the last alien:
- `wave < 3`  → transition → setup next wave aliens only.
- `wave == 3` → `level += 1`, `wave = 1` → transition → rebuild shields + wave-1
  aliens.

## Out of scope

- New enemy art or power-up types.
- Sound.
- Landscape support (explicitly removing the landscape assumption; game is
  portrait-only).
