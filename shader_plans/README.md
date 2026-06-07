# Shader Plan Queue System

Dated shader plan files to track pending, in-progress, and completed shader implementations.

## File Naming Convention

```
shader_plans/
├── README.md                          # This file - system documentation
├── queue.json                         # Queue index - tracks status of all plans
├── 2026-03-05_hyper-labyrinth.md     # Completed plan (date prefix)
├── 2026-03-06_chronos-labyrinth.md   # Completed plan
├── 2026-03-07_celestial-forge.md     # Pending implementation
└── 2026-03-08_bioluminescent-abyss.md # Next in queue
```

## Workflow

### 1. Morning - Create Plan
Scheduled task creates: `shader_plans/YYYY-MM-DD_shader-name.md`

### 2. Daytime - Review
- Review the plan
- If approved → Update `queue.json` status to "approved"
- If rejected → Update status to "rejected", remove file

### 3. Evening - Implement
- Check `queue.json` for oldest "approved" plan
- Implement that shader only
- Update status to "completed"
- Remove from queue or archive

## queue.json Structure

```json
{
  "current": "2026-03-07_celestial-forge",
  "queue": [
    {
      "id": "celestial-forge",
      "date": "2026-03-07",
      "file": "2026-03-07_celestial-forge.md",
      "status": "approved",
      "created_at": "2026-03-07T08:00:00Z"
    },
    {
      "id": "bioluminescent-abyss",
      "date": "2026-03-08",
      "file": "2026-03-08_bioluminescent-abyss.md",
      "status": "pending_review",
      "created_at": "2026-03-08T08:00:00Z"
    }
  ],
  "completed": [
    {
      "id": "chronos-labyrinth",
      "date": "2026-03-06",
      "file": "2026-03-06_chronos-labyrinth.md",
      "implemented": "2026-03-06T20:30:00Z",
      "shader_file": "gen-chronos-labyrinth.wgsl"
    }
  ],
  "rejected": []
}
```

## Status Values

- `pending_review` - Just created, needs review
- `approved` - Ready to implement
- `in_progress` - Currently being implemented
- `completed` - Shader implemented and merged
- `rejected` - Won't be implemented
- `hold` - Paused, implement later

## Rules

1. **FIFO Order**: Implement oldest `approved` plan first
2. **No Skipping**: Can't implement plan N+1 before plan N is done
3. **Daily Limit**: Only create one plan per day
4. **No Overwrite**: Each plan gets its own dated file
5. **Clean Queue**: Remove rejected plans or move to archive/
