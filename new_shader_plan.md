# New Shader Plan System

> **⚠️ DEPRECATED: Single File Format**
> 
> The old system used this single `new_shader_plan.md` file, which caused issues when multiple plans stacked up or when one wasn't implemented before the next was created.
> 
> **NEW SYSTEM: Dated Plan Files in `shader_plans/`**

---

## New Workflow

### For Automated Tasks (Creating Plans)

Instead of overwriting this file, create a new dated file:

```bash
# Create dated plan file
DATE=$(date +%Y-%m-%d)
SHADER_NAME="celestial-forge"
FILE="shader_plans/${DATE}_${SHADER_NAME}.md"

# Create the plan file
cat > "$FILE" << 'EOF'
# Plan: Celestial Forge Shader

## Metadata
- **ID:** gen-celestial-forge
- **Date:** 2026-03-07
- **Status:** pending_review
...
EOF

# Add to queue
# (Update shader_plans/queue.json via script)
```

### For Humans (Reviewing Plans)

1. Check `shader_plans/queue.json` for pending plans
2. Review the `.md` file
3. Change status to `"approved"` or `"rejected"`

### For Implementation

1. Find oldest `"approved"` plan in `queue.json`
2. Implement only that shader
3. Mark as `"completed"` with timestamp

---

## Directory Structure

```
shader_plans/
├── README.md                      # System documentation
├── queue.json                     # Queue index
├── 2026-03-06_chronos-labyrinth.md   ✓ Completed
├── 2026-03-07_celestial-forge.md     ⏳ Approved (next to implement)
├── 2026-03-08_quantum-foam.md        ⏳ Pending review
└── archive/                       # Old completed plans (optional)
```

---

## Queue Status Values

| Status | Meaning | Action |
|--------|---------|--------|
| `pending_review` | Just created | Review and approve/reject |
| `approved` | Ready to build | Implement this one first |
| `in_progress` | Building now | Only one at a time |
| `completed` | Done | Archived |
| `rejected` | Won't build | Remove or document why |
| `on_hold` | Paused | Skip for now |

---

## Key Rules

1. **One plan = One file** - Never overwrite, always create new dated file
2. **FIFO order** - Implement oldest approved plan first
3. **No skipping** - Can't jump ahead in the queue
4. **Status gate** - Only implement `approved` plans, not `pending_review`
5. **Daily limit** - Max one new plan per day

---

## Migration Notes

- **Chronos Labyrinth** (2026-03-06) was the last plan using the old system
- It has been moved to `shader_plans/2026-03-06_chronos-labyrinth.md`
- The shader was implemented as `gen-chronos-labyrinth.wgsl`
- Future plans use the new dated file system
