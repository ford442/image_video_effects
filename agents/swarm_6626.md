# Swarm Coordination — 2026-06-07 UPDATE

**Date:** 2026-06-07

**Focus:** Multi-agent swarm to upgrade generative shaders with **psychedelic/brilliant/bright color schemes** + **more movement/dynamic effects** + **expanded WGSL functions**.

**Philosophy:** Upgrade > Create new (we already have 320+ generative shaders). Make existing ones **pop harder**.

---

## Strategic Priorities (Today)

| Priority | Area | Goal | Owner | Status |
|----------|------|------|-------|--------|
| P1 | Ethereal Silk Showcase | Deliver flagship showcase shader | Kimi Claw | 🔄 In Progress |
| P2 | Psychedelic Color Upgrade | Batch-upgrade 20+ shaders with bright/psychedelic color schemes | Multi-Agent Swarm | 📋 Ready to Start |
| P3 | Movement & Dynamics | Add more motion, oscillation, organic flow to static shaders | Multi-Agent Swarm | 📋 Ready to Start |
| P4 | WGSL Function Library | Expand reusable functions (noise, color, shaping) | Codex | 📋 Ready to Start |
| P5 | Chromatic + DataTexture | Continue Batch 3 upgrades | Claude | 🔄 In Progress |

---

## 🎯 NEW: Psychedelic Color Swarm Plan

### Objective
Transform existing generative shaders from "subtle/ambient" to **striking, psychedelic, attention-grabbing** while maintaining quality.

### Color Direction
- **Neon gradients**: Electric purple → Hot pink → Cyan
- **Heat maps**: Deep blue → Yellow → White (thermal vision)
- **Bioluminescent**: Deep ocean blue → Teal → Bright green (glow)
- **Sunset neon**: Magenta → Orange → Gold (high contrast)
- **Acid trip**: Saturated complementary pairs (cyan/red, magenta/green)

### Movement Direction
- Add **oscillation** (sine/cosine time-based motion) to static patterns
- Add **organic drift** (simplex noise displacement) to rigid geometry
- Add **pulse/breathe** (scale + intensity modulation) to flat colors
- Add **trails/feedback** (temporal accumulation) to sharp effects

### WGSL Function Expansion
Create reusable functions in `agents/WGSL_BUILTINS_GENERATIVE.md`:
- `psychedelicPalette(t)` — time-rotating HSV rainbow
- `neonGlow(color, intensity)` — bloom-style glow
- `organicDrift(uv, time, scale)` — noise-based displacement
- `pulseScale(time, speed)` — breathing/pulsing animation
- `chromaticAberration(uv, amount)` — RGB split effect

---

## Multi-Agent Swarm Roles

### Kimi Claw
| Task | Status | Details |
|------|--------|---------|
| Ethereal Silk | 🔄 In Progress | Complete first, then join swarm |
| Color scheme reference guide | To Do | Document "best psychedelic combos" for other agents |
| Showcase shader #2 (Fractal Ember) | Backlog | After color swarm runs |

### Claude
| Task | Status | Details |
|------|--------|---------|
| Batch 3 E1-E3 | 🔄 In Progress | translucent-nebula, prismatic-crystal, electric-eel |
| Color upgrade pass | To Do | Apply psychedelic color schemes to Batch 3 shaders |
| Validate color upgrades | To Do | Check color upgrades don't break naga |

### Codex
| Task | Status | Details |
|------|--------|---------|
| WGSL function library | To Do | Add psychedelic/reusable functions to builtins doc |
| High-volume color upgrades | To Do | Apply color + movement to 20+ shaders (Batch 4: "Psychedelic Pass") |
| Performance check | To Do | Ensure bright colors don't tank performance |

### YOU (Human/Coordinator)
| Task | Status | Details |
|------|--------|---------|
| Approve color direction | Ready | Pick 2-3 color families to prioritize |
| Review swarm output | Ready | Check upgraded shaders meet quality bar |
| Merge + ship | Ready | Approve PRs when ready |

---

## Execution Plan

### Phase 1: Foundation (Next 30 min)
1. **Kimi Claw**: Finish Ethereal Silk
2. **Codex**: Add `psychedelicPalette`, `neonGlow`, `organicDrift` to `WGSL_BUILTINS_GENERATIVE.md`
3. **Claude**: Complete E1-E3 + add color upgrade pass

### Phase 2: Swarm Attack (Next 2 hours)
1. **Codex**: Bulk-apply color upgrades to 20 shaders (Batch 4: "Psychedelic Pass")
2. **Claude**: Validate + fix any naga breaks from color changes
3. **Kimi Claw**: Generate showcase shader #2 (Fractal Ember) with new color functions

### Phase 3: Polish (Next 1 hour)
1. **All agents**: Review upgraded shaders
2. **Claude**: Run validation pass (naga + feature flags + JSON sync)
3. **Kimi Claw**: Review audio reactivity on upgraded shaders

---

## Reference Documents

- `WGSL_BUILTINS_GENERATIVE.md` — Core standards + NEW psychedelic functions
- `agents/prompt-showcase-batch-1.md` — Showcase shader generation prompt
- `agents/showcase-checklist-v1.md` — Quality checklist
- `agents/design-ethereal-silk.md` — Ethereal Silk reference standard
- `agents/swarm-outputs/` — Validation reports

---

## Notes / Decisions

- **Color upgrade strategy**: We don't replace existing colors — we add **alternate color modes** via `zoomParam` toggles or `dataTextureA` switchable palettes. This preserves original aesthetics while adding psychedelic options.
- **Performance guardrail**: Bright colors + more movement = more GPU work. Add `performance check` step to all color upgrades.
- **User preference**: User explicitly requested "psychedelic/brilliant/bright" — this is the direction, not a suggestion.

---

**Next Sync:** After Ethereal Silk delivered OR after Codex completes WGSL function library additions.

---

## 📊 Swarm Progress Tracker

| Agent | Task | Status | Last Update | Notes |
|-------|------|--------|-------------|-------|
| **Codex** | Add 5 psychedelic functions to WGSL_BUILTINS | 📋 Ready | 2026-06-07 | Waiting for execution |
| **Claude** | Batch 3 E1-E3 + Color Upgrade | 📋 Ready | 2026-06-07 | Waiting for execution |
| **Kimi Claw** | Ethereal Silk + Neon mode | 🔄 In Progress | 2026-06-07 | Generating... |
| **You** | Approve/Review | 🎯 Ready | 2026-06-07 | Review output when ready |

### Design Docs Ready
- ✅ `design-ethereal-silk.md` — Ethereal Silk reference
- ✅ `design-fractal-ember.md` — Fractal Ember reference
- ✅ `design-nebula-pulse.md` — Nebula Pulse reference

### Batch Status
- **Batch 3 (Chromatic+DataTexture)**: E1-E3 in progress, D1-D5 done
- **Batch 4 (Psychedelic Color Pass)**: Ready to start after functions land
- **Showcase Shaders**: Ethereal Silk in progress, Fractal Ember + Nebula Pulse queued

### Upcoming Tasks
- [ ] Ethereal Silk delivered + reviewed
- [ ] Codex functions merged into WGSL_BUILTINS
- [ ] Claude E1-E3 color upgrades validated
- [ ] Fractal Ember design doc approved
- [ ] Nebula Pulse design doc approved
- [ ] Fractal Ember generated (Kimi Claw)
- [ ] Nebula Pulse generated (Kimi Claw)
- [ ] Showcase audio reactivity review
