# Generative Shader Upgrade Swarm — Batch 2 — 2026-06-29

## Mission
Upgrade four more modern generative shaders with new **complexity** and/or **beauty** while preserving their original soul. Each shader is owned by one specialist agent. Outputs are written to this directory for review before promotion.

## Required Reading (every agent)
1. `agents/WGSL_BUILTINS_GENERATIVE.md` — canonical 13-binding header, compute-safe built-ins, anti-patterns.
2. `agents/4_AGENT_SWARM_PROMPT.md` — swarm roles and quality checklists.
3. Your assigned source WGSL + JSON (see below).

## Agent Assignments

| Agent | Specialty | Target Shader | Source WGSL | Source JSON | Output Dir |
|-------|-----------|---------------|-------------|-------------|------------|
| Algorithmist | Advanced math, simulation depth, SDF/fractal upgrades | gen-newton-fractal | `public/shaders/gen-newton-fractal.wgsl` | `shader_definitions/generative/gen-newton-fractal.json` | `agents/swarm-outputs/generative-upgrade-2026-06-29-batch2/algorithmist/` |
| Visualist | HDR color, lighting, atmospheric/emotional impact | gen-minimal-surface-soap-iridescence | `public/shaders/gen-minimal-surface-soap-iridescence.wgsl` | `shader_definitions/generative/gen-minimal-surface-soap-iridescence.json` | `agents/swarm-outputs/generative-upgrade-2026-06-29-batch2/visualist/` |
| Interactivist | Mouse/audio/video reactivity, feedback loops, emergent behavior | gen-acid-lissajous | `public/shaders/gen-acid-lissajous.wgsl` | `shader_definitions/generative/gen-acid-lissajous.json` | `agents/swarm-outputs/generative-upgrade-2026-06-29-batch2/interactivist/` |
| Optimizer | Performance, elegance, pipeline integration, LOD | gen-quantum-foam | `public/shaders/gen-quantum-foam.wgsl` | `shader_definitions/generative/gen-quantum-foam.json` | `agents/swarm-outputs/generative-upgrade-2026-06-29-batch2/optimizer/` |

## Output Requirements
Each agent must produce exactly these files in their output dir:

1. `{shader-id}.wgsl` — complete, self-contained, upgraded WGSL.
2. `{shader-id}.json` — complete, upgraded JSON metadata.
3. `README.md` — brief changelog: what changed, why, performance estimate, dependencies on canonical patterns.

## WGSL Constraints (non-negotiable)
- Use the exact 13-binding header from `WGSL_BUILTINS_GENERATIVE.md` §0.
- `Uniforms` struct fields: `config`, `zoom_config`, `zoom_params`, `ripples`.
- Compute entry: `@compute @workgroup_size(16, 16, 1)`.
- Bounds guard using `global_id`/`pixel` vs `res`.
- Use `textureSampleLevel`, `textureLoad`, `textureStore` only.
- No `tan`, `textureSample`, `dpdx`, `dpdy`.
- Prefer `select`/`mix` over per-pixel branches.
- Semantic alpha: do not hardcode `1.0` unless opaque by design.

## JSON Constraints (non-negotiable)
- Keep original `id`, `name`, `category`, `url`.
- Add or preserve `updated: true`.
- `workgroup_size: [16, 16, 1]`.
- Four `updatedParams` entries (indices 0..3) with `name`, `default`, `min`, `max`, `step`.
- `supportsDepth: true/false`.
- `features: []` (or populate if meaningful).
- Update `description` to reflect new capabilities.

## Quality Targets
- Visual rating increase ≥ 0.5 stars (push noticeably).
- At least 2 techniques from the agent's toolkit integrated.
- 60fps at 1080p on mid-tier GPU (avoid heavy per-pixel loops).
- No naga/WGSL anti-patterns.

## Validation After Delivery
After all agents finish, the parent will run:
- `node scripts/generate_shader_lists.js`
- `python3 scripts/wgsl_precommit_gate.py --files <outputs>` (if naga available)
- JSON parse checks

## Coordination
- Agents work in parallel.
- Do not modify source files directly.
- If a technique requires a binding not in the canonical 13, fall back to a compute-safe alternative.
