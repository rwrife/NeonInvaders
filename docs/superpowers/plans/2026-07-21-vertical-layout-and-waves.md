# Vertical Layout & 3-Wave Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Neon Invaders a proper portrait game with fewer/larger enemies and shields, and 3 distinct waves per level.

**Architecture:** Unify the logical coordinate system to portrait (400×780) in `Renderer`, shrink the alien grid to 4×3 with larger sprites, reduce to 3 larger shields, and add a `wave` (1–3) concept to `GameEngine` with per-wave behavior modifiers. Wave/level transitions share the existing `levelTransition` phase via a flag.

**Tech Stack:** Swift, Metal (MetalKit), simd. No test harness; verification is by code review + manual play (build requires full Xcode, unavailable in this environment).

---

### Task 1: Unify coordinates to portrait

**Files:**
- Modify: `NeonInvaders Shared/Renderer.swift` (gameW/gameH + HUD/splash retune)

- [ ] **Step 1: Change logical dimensions**

In `Renderer.swift` change:
```swift
static let gameW: Float = 400
static let gameH: Float = 780
```

- [ ] **Step 2: Retune landscape-specific screen offsets**

Splash: title scale `ts` too large for 400 width (13 chars * 6 * 4.5 = 351, close). Reduce title `ts` to `3.0`, high-score column offsets, and alien-demo spacing so nothing exceeds width 400. HUD font sizes and life-icon spacing verified against W=400.

- [ ] **Step 3: Commit**

```bash
git commit -am "Unify renderer logical coords to portrait 400x780"
```

---

### Task 2: Shrink & enlarge alien formation (4×3)

**Files:**
- Modify: `NeonInvaders Shared/GameEngine.swift`

- [ ] **Step 1: Change grid constants**

```swift
let alienCols = 4
let alienRows = 3
let alienW: Float = 40
let alienH: Float = 28
let alienGapX: Float = 22
let alienGapY: Float = 20
```

- [ ] **Step 2: Update setupAliens row→type mapping for 3 rows**

Row 0 = squid, row 1 = crab, row 2 = octopus.

- [ ] **Step 3: Commit**

---

### Task 3: 3 larger shields

**Files:**
- Modify: `NeonInvaders Shared/GameEngine.swift` (Shield constants + setupShields)

- [ ] **Step 1: Enlarge shield pixel grid**

```swift
static let cols = 20
static let rows = 12
static let pixelSize: Float = 4.0
```

- [ ] **Step 2: Place 3 shields evenly**

Loop `0..<3`, center x at `W/4 * Float(i+1)`, arch carve scaled to new cols/rows.

- [ ] **Step 3: Commit**

---

### Task 4: Wave state + transitions

**Files:**
- Modify: `NeonInvaders Shared/GameEngine.swift`

- [ ] **Step 1: Add wave state**

```swift
var wave: Int = 1
var isLevelTransition = false   // true = advancing level, false = advancing wave
```

- [ ] **Step 2: Split setup**

`setupLevel()` rebuilds shields + resets wave to 1 + calls `setupWave()`. `setupWave()` sets up aliens/formation/ufo timers only (shields persist).

- [ ] **Step 3: Wave-clear logic**

In `updatePlaying`, when all aliens dead:
- if `wave < 3`: `wave += 1; isLevelTransition = false; levelTransitionTimer = 2.0; phase = .levelTransition`
- else: `level += 1; wave = 1; isLevelTransition = true; levelTransitionTimer = 2.5; phase = .levelTransition`

In `update` levelTransition case: call `setupLevel()` if `isLevelTransition` else `setupWave()`.

- [ ] **Step 4: Commit**

---

### Task 5: Per-wave dynamics

**Files:**
- Modify: `NeonInvaders Shared/GameEngine.swift`

- [ ] **Step 1: Wave 2 — Swarm dive-bombing**

Add `struct` fields for diving: reuse Alien with `isDiving`/`diveVel`. In `updateAliens`, wave 2 gets higher `formationVelX` and occasional random alien enters dive toward player x. Diving aliens ignore formation offset and move by their own velocity; removed off bottom.

- [ ] **Step 2: Wave 2 — faster/erratic horizontal**

Multiply base `formationVelX` and add small sinusoidal jitter for wave 2.

- [ ] **Step 3: Wave 3 — 2-hit aliens + guaranteed UFO + high fire**

Add `var hp: Int` to Alien (default 1; 2 on wave 3). `killAlien` decrements hp, applies damage tint, only dies at 0. Reduce shoot delay for wave 3. Force `ufoSpawnTimer` small on wave 3 setup.

- [ ] **Step 4: Commit**

---

### Task 6: HUD & banner wave indicator

**Files:**
- Modify: `NeonInvaders Shared/Renderer.swift`

- [ ] **Step 1: HUD "WAVE n/3"**

Add near the level readout in `drawHUD`.

- [ ] **Step 2: Wave banner**

In `drawLevelBanner`, show "WAVE n" when `!game.isLevelTransition`, else "LEVEL n".

- [ ] **Step 3: Commit**

---

## Verification

- Code review each file for compile-correctness (types, optionals, exhaustising switches).
- Confirm no logical coordinate exceeds 400 (x) / 780 (y) in HUD/splash.
- Manual play verification deferred to a machine with full Xcode.
