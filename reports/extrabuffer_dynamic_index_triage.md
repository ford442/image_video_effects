# extraBuffer dynamic-index triage

Generated from `reports/extrabuffer_dynamic_index_baseline.json` (32 write sites).
Machine-readable baseline is SoT; this file is documentation only.

## Verdict

All baselined dynamic-index writes use const-indexed spring/state slots at `extraBuffer[133..138]`.
Static analysis cannot prove the index stays in the safe zone; human triage accepted bounded slots.

## Baseline sections (`extrabuffer_write_audit_baseline.json`)

- **engine_owned** — 1 file(s): FFT-zone writes documented as engine/audio coupling. Do not add entries.
- **shader_bug** — 42 file(s): persistent state in reserved/FFT zone; remap to `[133..255]` when rewritten.

## Per-file dynamic writes

### `public/shaders/gen-percolation-threshold.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 83 | `gid.y` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 84 | `u32(latticeH) + gid.y` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

### `public/shaders/gen-physarum-sacred-geometry.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 120 | `agentIdx * 4u + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 121 | `agentIdx * 4u + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 122 | `agentIdx * 4u + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 123 | `agentIdx * 4u + 3u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 173 | `agentIdx * 4u + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 174 | `agentIdx * 4u + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 175 | `agentIdx * 4u + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

### `public/shaders/gen-wasm-hls-physarum-swarm.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 78 | `bufBase + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 79 | `bufBase + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 80 | `bufBase + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 81 | `bufBase + 3u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 133 | `bufBase + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 134 | `bufBase + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 135 | `bufBase + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

### `public/shaders/neon-cursor-trace.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 113 | `bufOff` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 114 | `bufOff + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 115 | `bufOff + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 116 | `bufOff + 3u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 117 | `bufOff + 4u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

### `public/shaders/physarum-gemini.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 158 | `idx * 4u + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 159 | `idx * 4u + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 160 | `idx * 4u + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 161 | `idx * 4u + 3u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

### `public/shaders/physarum-grokcf1.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 158 | `idx * 4u + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 159 | `idx * 4u + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 160 | `idx * 4u + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 161 | `idx * 4u + 3u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

### `public/shaders/physarum.wgsl`

| Line | Expression | Triage |
|-----:|------------|--------|
| 131 | `idx * 3u + 0u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 132 | `idx * 3u + 1u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |
| 133 | `idx * 3u + 2u` | const-indexed spring/state slots at extraBuffer[133..138]; static analysis cannot prove bound |

