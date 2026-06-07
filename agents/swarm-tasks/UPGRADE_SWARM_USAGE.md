# Shader Upgrade Swarm — Usage Guide

## Quick Start

```bash
# 1. Generate prompts for the next batch of pending shaders
npm run swarm:upgrade -- --prepare --batch=4

# 2. Review the generated prompts
ls swarm-tasks/prompts/

# 3. Get a JSON manifest for AI CLI Agent-tool dispatch
npm run swarm:upgrade -- --agent-dispatch --batch=4

# 4. (Optional) Dispatch via external AI API (requires OPENAI_API_KEY or ANTHROPIC_API_KEY)
npm run swarm:upgrade -- --dispatch --batch=4
```

---

## How It Works

The orchestrator (`scripts/run-upgrade-swarm.js`) reads `swarm-tasks/upgrade-queue.json`, picks the next pending batch, and generates a complete, self-contained prompt for each shader. Each prompt includes:

- The shader's current WGSL source code
- Its JSON definition
- The immutable 13-binding contract (must not be altered)
- Role-specific upgrade instructions (Algorithmist / Visualist / Interactivist / Optimizer)
- Output format requirements

---

## Modes

### `--prepare` (default)
Generates prompt files in `swarm-tasks/prompts/<shader-id>.md` without modifying any shader files. Use this to review prompts before dispatching agents.

### `--agent-dispatch`
Generates prompts and prints a JSON manifest to stdout. This manifest can be used by an AI CLI (or manual process) to spawn parallel subagents. Each manifest entry contains:
- `id`: Shader ID
- `agent_role`: Assigned specialization
- `prompt_length`: Size of the generated prompt
- `prompt_file`: Absolute path to the prompt markdown file

### `--dispatch`
Attempts to spawn parallel Node.js workers that call an external AI API (OpenAI or Anthropic). Requires `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` in the environment. If no key is set, falls back to `--prepare`.

---

## Queue Management

The queue lives in `swarm-tasks/upgrade-queue.json`. Each item has:

| Field | Description |
|-------|-------------|
| `id` | Shader filename (without `.wgsl`) |
| `size` | Current file size in bytes |
| `status` | `pending`, `assigned`, `completed`, or `validated` |
| `priority` | 1 = highest, 4 = lowest |
| `agent_role` | Which agent specialization handles this shader |
| `target_lines` | Rough target line count for the upgrade |

### Adding More Shaders

Edit `swarm-tasks/upgrade-queue.json` and append new items. The candidate pool in `agents/weekly_upgrade_swarm.md` contains additional shaders ready for upgrade.

### Resetting Status

To re-process a shader, set its `status` back to `pending` in the queue file.

---

## Agent Roles

| Role | Focus | Located In |
|------|-------|------------|
| **Algorithmist** | Math, noise, SDFs, fractals, simulations | `agents/prompt-templates/algorithmist.md` |
| **Visualist** | Color science, lighting, atmosphere, tone mapping | `agents/prompt-templates/visualist.md` |
| **Interactivist** | Mouse, audio, depth, feedback loops | `agents/prompt-templates/interactivist.md` |
| **Optimizer** | Performance, code elegance, pipeline integration | `agents/prompt-templates/optimizer.md` |

---

## Validation Pipeline

When `--dispatch` is used and shaders are modified, the orchestrator automatically runs:

1. `node scripts/generate_shader_lists.js` — validates JSON manifests and WGSL existence
2. `node scripts/check_duplicates.js` — ensures no duplicate shader IDs
3. `naga <shader>` — validates WGSL syntax (if Naga is installed)
4. Custom binding check — verifies the 13-binding contract is intact

---

## Progress Tracking

Every run appends an entry to `swarm-outputs/upgrade-progress.json`. This file is safe to keep in git — it only contains metadata (timestamps, batch IDs, counts).

---

## Example Workflow

```bash
# Step 1: Prepare the first batch
npm run swarm:upgrade -- --prepare --batch=4

# Step 2: Inspect a prompt
cat swarm-tasks/prompts/phosphor-decay.md

# Step 3: Get manifest for AI subagent dispatch
npm run swarm:upgrade -- --agent-dispatch --batch=4

# Step 4: (After subagents finish and write upgraded files)
# Run validation manually:
node scripts/generate_shader_lists.js
node scripts/check_duplicates.js
naga public/shaders/phosphor-decay.wgsl

# Step 5: Mark completed shaders in the queue, then repeat
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `WGSL file not found` | Ensure the shader ID in the queue matches a file in `public/shaders/` |
| `JSON file not found` | The shader may not have a definition yet. The prompt will note this; create one in `shader_definitions/<category>/` |
| Naga not installed | Install with `cargo install naga-cli` or skip — the orchestrator will still run JS validations |
| API key missing | Set `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` in your environment for `--dispatch` |

---

## Success Criteria

A swarm run is successful when:
- All prompt files are generated without errors
- Prompts contain the full current WGSL source, binding contract, and role instructions
- Validation pipeline passes after upgrades are applied
- Queue status is updated and progress is persisted
