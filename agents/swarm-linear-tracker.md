# Shader Upgrade Swarm — Linear Tracker

> **Active Batch:** JUL-185 (Phase-A RGBA Foundation, 20 shaders)  
> **Previous Batch:** JUL-168 (23 shaders, 3 remaining: chroma-vortex, split-dimension, spectral-smear)  
> **Created:** 2026-05-23  
> **Team:** Jules_1inkus

---

## Active Batch Dashboard (JUL-185)

| # | Shader | Agent Role | Linear Issue | Status | Agent |
|---|--------|-----------|--------------|--------|-------|
| 1 | `magnetic-interference` | Interactivist | [JUL-186](https://linear.app/jules-1inkus/issue/JUL-186) | 🟡 In Progress | — |
| 2 | `cyber-lattice` | Visualist | [JUL-187](https://linear.app/jules-1inkus/issue/JUL-187) | 🟡 In Progress | — |
| 3 | `quantum-field-visualizer` | Algorithmist | [JUL-188](https://linear.app/jules-1inkus/issue/JUL-188) | 🟡 In Progress | — |
| 4 | `volumetric-god-rays` | Visualist | [JUL-189](https://linear.app/jules-1inkus/issue/JUL-189) | 🟡 In Progress | — |
| 5 | `luma-slice-interactive` | Interactivist | [JUL-191](https://linear.app/jules-1inkus/issue/JUL-191) | 🟡 In Progress | — |
| 6 | `dynamic-halftone` | Optimizer | [JUL-190](https://linear.app/jules-1inkus/issue/JUL-190) | 🟡 In Progress | — |
| 7 | `steampunk-gear-lens` | Visualist | [JUL-193](https://linear.app/jules-1inkus/issue/JUL-193) | 🟡 In Progress | — |
| 8 | `spectrogram-displace-pass2` | Interactivist | [JUL-196](https://linear.app/jules-1inkus/issue/JUL-196) | 🟡 In Progress | — |
| 9 | `heat-haze` | Algorithmist | [JUL-198](https://linear.app/jules-1inkus/issue/JUL-198) | 🟡 In Progress | — |
| 10 | `bio-touch` | Interactivist | [JUL-200](https://linear.app/jules-1inkus/issue/JUL-200) | 🟡 In Progress | — |
| 11 | `data-stream` | Algorithmist | [JUL-201](https://linear.app/jules-1inkus/issue/JUL-201) | 🟡 In Progress | — |
| 12 | `spectral-rain` | Visualist | [JUL-202](https://linear.app/jules-1inkus/issue/JUL-202) | 🟡 In Progress | — |
| 13 | `circular-pixelate` | Optimizer | [JUL-203](https://linear.app/jules-1inkus/issue/JUL-203) | 🟡 In Progress | — |
| 14 | `cyber-halftone-scanner` | Visualist | [JUL-204](https://linear.app/jules-1inkus/issue/JUL-204) | 🟡 In Progress | — |
| 15 | `speed-lines-focus` | Optimizer | [JUL-205](https://linear.app/jules-1inkus/issue/JUL-205) | 🟡 In Progress | — |
| 16 | `scanline-drift` | Visualist | [JUL-206](https://linear.app/jules-1inkus/issue/JUL-206) | 🟡 In Progress | — |
| 17 | `gen-bioluminescent-reaction-diffusion` | Algorithmist | [JUL-208](https://linear.app/jules-1inkus/issue/JUL-208) | 🟡 In Progress | — |
| 18 | `gen-psychedelic-layered-time-stamps` | Interactivist | [JUL-207](https://linear.app/jules-1inkus/issue/JUL-207) | 🟡 In Progress | — |
| 19 | `ripple-blocks` | Interactivist | [JUL-209](https://linear.app/jules-1inkus/issue/JUL-209) | 🟡 In Progress | — |
| 20 | `moire-interference` | Algorithmist | [JUL-210](https://linear.app/jules-1inkus/issue/JUL-210) | 🟡 In Progress | — |

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
