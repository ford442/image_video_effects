# Shader Upgrade Swarm — Linear Tracker

> **Active Batch:** JUL-185 (Phase-A RGBA Foundation, 20 shaders)  
> **Previous Batch:** JUL-168 (23 shaders, 3 remaining: chroma-vortex, split-dimension, spectral-smear)  
> **Created:** 2026-05-23  
> **Team:** Jules_1inkus

---

## Active Batch Dashboard (JUL-185)

| # | Shader | Agent Role | Linear Issue | Status | Agent |
|---|--------|-----------|--------------|--------|-------|
| 1 | `magnetic-interference` | Interactivist | [JUL-186](https://linear.app/jules-1inkus/issue/JUL-186) | ✅ Done | — |
| 2 | `cyber-lattice` | Visualist | [JUL-187](https://linear.app/jules-1inkus/issue/JUL-187) | ✅ Done | — |
| 3 | `quantum-field-visualizer` | Algorithmist | [JUL-188](https://linear.app/jules-1inkus/issue/JUL-188) | ✅ Done | — |
| 4 | `volumetric-god-rays` | Visualist | [JUL-189](https://linear.app/jules-1inkus/issue/JUL-189) | ✅ Done | — |
| 5 | `luma-slice-interactive` | Interactivist | [JUL-191](https://linear.app/jules-1inkus/issue/JUL-191) | ✅ Done | — |
| 6 | `dynamic-halftone` | Optimizer | [JUL-190](https://linear.app/jules-1inkus/issue/JUL-190) | ✅ Done | — |
| 7 | `steampunk-gear-lens` | Visualist | [JUL-193](https://linear.app/jules-1inkus/issue/JUL-193) | ✅ Done | — |
| 8 | `spectrogram-displace-pass2` | Interactivist | [JUL-196](https://linear.app/jules-1inkus/issue/JUL-196) | ✅ Done | — |
| 9 | `heat-haze` | Algorithmist | [JUL-198](https://linear.app/jules-1inkus/issue/JUL-198) | ✅ Done | — |
| 10 | `bio-touch` | Interactivist | [JUL-200](https://linear.app/jules-1inkus/issue/JUL-200) | ✅ Done | — |
| 11 | `data-stream` | Algorithmist | [JUL-201](https://linear.app/jules-1inkus/issue/JUL-201) | ✅ Done | — |
| 12 | `spectral-rain` | Visualist | [JUL-202](https://linear.app/jules-1inkus/issue/JUL-202) | ✅ Done | — |
| 13 | `circular-pixelate` | Optimizer | [JUL-203](https://linear.app/jules-1inkus/issue/JUL-203) | ✅ Done | — |
| 14 | `cyber-halftone-scanner` | Visualist | [JUL-204](https://linear.app/jules-1inkus/issue/JUL-204) | ✅ Done | — |
| 15 | `speed-lines-focus` | Optimizer | [JUL-205](https://linear.app/jules-1inkus/issue/JUL-205) | ✅ Done | — |
| 16 | `scanline-drift` | Visualist | [JUL-206](https://linear.app/jules-1inkus/issue/JUL-206) | ✅ Done | — |
| 17 | `gen-bioluminescent-reaction-diffusion` | Algorithmist | [JUL-208](https://linear.app/jules-1inkus/issue/JUL-208) | ✅ Done | — |
| 18 | `gen-psychedelic-layered-time-stamps` | Interactivist | [JUL-207](https://linear.app/jules-1inkus/issue/JUL-207) | ✅ Done | — |
| 19 | `ripple-blocks` | Interactivist | [JUL-209](https://linear.app/jules-1inkus/issue/JUL-209) | ✅ Done | — |
| 20 | `moire-interference` | Algorithmist | [JUL-210](https://linear.app/jules-1inkus/issue/JUL-210) | ✅ Done | — |

## Unclaimed from Previous Batch (JUL-168)

| Shader | Status |
|--------|--------|
| `chroma-vortex` | 🔵 Pending |
| `split-dimension` | 🔵 Pending |
| `spectral-smear` | 🔵 Pending |

---

## Agent Assignment Log

| Timestamp | Agent | Shader | Action |
|-----------|-------|--------|--------|
| | | | |

---

## Status Key

- 🔵 **Backlog** — Not started
- 🟡 **In Progress** — Agent actively working
- 🟠 **In Review** — Completed, awaiting verification
- 🟢 **Done** — Merged and verified
- 🔴 **Blocked** — Waiting on dependency

---

## Watching Other Agents

To see what other agents are working on:
1. Open [JUL-185](https://linear.app/jules-1inkus/issue/JUL-185) in Linear
2. Check the **Related** tab for linked issues
3. Or filter issues by label `shader` + status `In Progress`

---

## Quick Commands

```bash
# Check queue status
cat swarm-tasks/phase-a-queue.json | python3 -c "
import sys, json
d = json.load(sys.stdin)
for s in ['pending', 'in_progress', 'completed']:
    c = sum(1 for i in d['items'] if i['status'] == s)
    print(f'{s}: {c}')
"
```

## Batch G — JUL-257 (2026-05-23)

| # | Shader | Linear | Agent | Status |
|---|--------|--------|-------|--------|
| 1 | `chromatic-phase-inversion` | JUL-258 | Optimizer | 🟡 In Progress |
| 2 | `holographic-shatter` | JUL-259 | Visualist | 🟡 In Progress |
| 3 | `liquid-displacement` | JUL-260 | Algorithmist | 🟡 In Progress |
| 4 | `navier-stokes-dye` | JUL-261 | Algorithmist | 🟡 In Progress |
| 5 | `recursion-mirror-vortex` | JUL-262 | Optimizer | 🟡 In Progress |
| 6 | `spectral-bleed-confinement` | JUL-263 | Visualist | 🟡 In Progress |
| 7 | `temporal_echo` | JUL-264 | Interactivist | 🟡 In Progress |
| 8 | `tensor-flow-sculpt` | JUL-265 | Algorithmist | 🟡 In Progress |
| 9 | `tensor-flow-sculpting` | JUL-266 | Algorithmist | 🟡 In Progress |
| 10 | `moire-interference` | JUL-267 | Optimizer | 🟡 In Progress |
| 11 | `scanline-drift` | JUL-268 | Interactivist | 🟡 In Progress |
| 12 | `speed-lines-focus` | JUL-269 | Optimizer | 🟡 In Progress |
| 13 | `gen-magnetic-ferrofluid` | JUL-270 | Algorithmist | 🟡 In Progress |
| 14 | `oscilloscope-overlay` | JUL-271 | Interactivist | 🟡 In Progress |
| 15 | `quantum-ripples` | JUL-272 | Interactivist | 🟡 In Progress |
| 16 | `sim-fluid-feedback-field-pass3` | JUL-273 | Algorithmist | 🟡 In Progress |
| 17 | `gen-abyssal-chrono-coral` | JUL-274 | Algorithmist | 🟡 In Progress |
| 18 | `gen-audio-spirograph` | JUL-275 | Interactivist | 🟡 In Progress |
| 19 | `gen-bioluminescent-aether-pulsar` | JUL-276 | Visualist | 🟡 In Progress |
| 20 | `gen-chromodynamic-plasma-collider` | JUL-277 | Visualist | 🟡 In Progress |

**Parent:** JUL-257
