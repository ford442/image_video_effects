# Swarm Coordination — 2026-06-06

**Date:** 2026-06-06  
**Focus:** Shift toward **upgrading & optimizing** existing generative shaders + building flagship showcase shaders.  
**Philosophy:** Upgrade > Create new (we already have 320+ generative shaders).

## Strategic Priorities (This Week)

| Priority | Area | Goal | Owner |
|---------|------|------|-------|
| P1 | Batch 3 Upgrades | Complete chromatic + dataTextureA + temporal feedback on remaining shaders | Claude + Codex |
| P2 | Showcase Quality | Deliver 2–3 high-quality flagship showcase shaders | Kimi Claw |
| P3 | Performance & Structure | Audit + improve logical structure and performance on older shaders | Codex |
| P4 | Audio Reactivity | Improve consistency of audio mapping across upgraded shaders | All |
| P5 | Documentation | Maintain clear task tracking and standards | All |

---

## Agent Task Board

### Kimi Claw
**Role:** Creative direction + high-quality showcase shader creation

| Task | Status | Details | Notes |
|------|--------|---------|-------|
| Generate **Ethereal Silk** | To Do | Organic flowing silk/veil effect. Strong idle + satisfying mouse claim | Use updated prompt in `agents/prompt-showcase-batch-1.md` |
| Generate **Fractal Ember** | Backlog | Fractal crystal lattice with shatter/reform on claim | Only if Ethereal Silk quality is high |
| Maintain showcase prompt template | Ongoing | Keep `agents/prompt-showcase-batch-1.md` updated | — |
| Review new showcase shaders for audio reactivity | Backlog | Ensure good zoomParam1-4 mapping | After first shader is done |

### Claude
**Role:** Systematic batch upgrades + validation

| Task | Status | Details | Notes |
|------|--------|---------|-------|
| Complete **Batch 3D** (D1–D5) | Done | 5 shaders upgraded + naga validated | Includes Conway fix |
| Unblock & complete **E1-E3** | In Progress | translucent-nebula, prismatic-crystal, electric-eel | Waiting on Kimi Claw notes |
| Continue **Batch 3 Priority B** | To Do | Shaders missing `dataTextureA` writeback (124 total) | Start with highest impact ones |
| Run validation pass | Ongoing | naga + feature flag + JSON sync check | After each batch |

### Codex
**Role:** High-volume cleanup, performance, and structure work

| Task | Status | Details | Notes |
|------|--------|---------|-------|
| Metadata drift verification | To Do | Confirm 0 drift after recent batches | Run audit script |
| Performance audit (selected shaders) | Backlog | Identify expensive patterns in older generative shaders | Focus on frequently used ones |
| Logical structure cleanup | Backlog | Naming, dead code, duplicated functions, consistency | Start with Batch 3 shaders |
| Help with `dataTextureA` writeback fixes | To Do | Support Claude on Priority B shaders | — |

### Shared / Coordination Tasks

| Task | Status | Owner | Details |
|------|--------|-------|---------|
| Create & maintain `swarm_6626.md` | Done | — | This file |
| Define "Showcase Readiness" criteria | To Do | All | What makes a shader good for 12s rotation |
| Update `WGSL_BUILTINS_GENERATIVE.md` if needed | Backlog | — | Add new patterns discovered during upgrades |
| Review GitHub Issues #799, #800, #801 | To Do | — | Decide priority vs current work |

---

## Reference Documents

- `WGSL_BUILTINS_GENERATIVE.md` — Core standards
- `agents/prompt-showcase-batch-1.md` — Showcase shader generation prompt
- `agents/showcase-checklist-v1.md` — Quality checklist for new/updated shaders
- GitHub Issue #801 — Batch 3 planning
- `agents/swarm-outputs/` — Validation reports and audit results

---

## Notes / Decisions

- We are deliberately slowing down new shader creation in favor of upgrading the existing library.
- Flagship showcase shaders (like Molten Gold) are still valuable as quality references.
- Performance and logical cleanliness are now explicit upgrade criteria alongside feature completeness.

---

**Next Sync:** After Ethereal Silk is delivered or Batch 3 E1-E3 is unblocked.
