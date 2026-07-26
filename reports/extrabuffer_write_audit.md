# extraBuffer Write Audit

- Files scanned: 1
- **New violations (writes to [0..132]): 1**
- Known (triaged baseline) violations: 0
- Dynamic-index writes (unresolved, review): 0
- Out-of-range writes (>255): 0

## New violations

- `public/shaders/_audit_probe.wgsl:3` — `extraBuffer[7] =` → index 7 (fft-zone)

