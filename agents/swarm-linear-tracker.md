# Shader Upgrade Swarm — Linear Tracker

> **Batch:** JUL-159 (Phase-A RGBA Foundation, 8 shaders)  
> **Created:** 2026-05-23  
> **Team:** Jules_1inkus

---

## Batch Dashboard

| # | Shader | Agent Role | Linear Issue | Status | Agent |
|---|--------|-----------|--------------|--------|-------|
| 1 | `gen-magnetic-field-warp` | Algorithmist | [JUL-160](https://linear.app/jules-1inkus/issue/JUL-160) | 🟡 In Progress | — |
| 2 | `gen-dynamic-tessellation-ornate-fractal-tiles` | Visualist | [JUL-161](https://linear.app/jules-1inkus/issue/JUL-161) | 🟡 In Progress | — |
| 3 | `gen-neural-network-glow-synaptic-pulse` | Interactivist | [JUL-162](https://linear.app/jules-1inkus/issue/JUL-162) | 🟡 In Progress | — |
| 4 | `interactive-fisheye` | Optimizer | [JUL-163](https://linear.app/jules-1inkus/issue/JUL-163) | 🟡 In Progress | — |
| 5 | `entropy-grid` | Algorithmist | [JUL-164](https://linear.app/jules-1inkus/issue/JUL-164) | 🟡 In Progress | — |
| 6 | `swirling-void` | Visualist | [JUL-165](https://linear.app/jules-1inkus/issue/JUL-165) | 🟡 In Progress | — |
| 7 | `double-exposure-zoom` | Interactivist | [JUL-166](https://linear.app/jules-1inkus/issue/JUL-166) | 🟡 In Progress | — |
| 8 | `quad-mirror` | Optimizer | [JUL-167](https://linear.app/jules-1inkus/issue/JUL-167) | 🟡 In Progress | — |

---

## Agent Assignment Log

Use this section to claim shaders. When you start work on a shader, update its **Agent** column with your identifier and move the Linear issue to **In Progress**.

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
1. Open [JUL-159](https://linear.app/jules-1inkus/issue/JUL-159) in Linear
2. Check the **Related** tab for linked issues
3. Or filter issues by label `shader` + status `In Progress`

---

## Commands

```bash
# Refresh this tracker from Linear
curl -s ...  # (manual refresh via Linear UI recommended)

# View swarm queue status
cat swarm-tasks/phase-a-queue.json | python3 -c "
import sys, json
d = json.load(sys.stdin)
pending = [i for i in d['items'] if i['status'] == 'pending']
print(f'Phase A remaining: {len(pending)}')
"
```
