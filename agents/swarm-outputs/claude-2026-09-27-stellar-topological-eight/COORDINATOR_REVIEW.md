# COORDINATOR_REVIEW — Stellar / Topological Eight (2026-09-27)

Checked by the coordinator against the WGSL/JSON on disk, not from agent reports. **No GPU: every visual claim is unverified.**

| Check (§9) | forge | ouroboros | web-loom | reef | tectonic | phase-weave | cathedral | physarum |
|---|---|---|---|---|---|---|---|---|
| Idea Card exists | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Card written before diff (mtime) | ✓ | **unverifiable** (equal mtimes; card and diff agree) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Each idea findable (`IDEA` tags) | 3 | 3 | 6 | 7 | 9 | 5 | 4 | 3 |
| KEEP VERBATIM holds (per agent + diff sizes +27…+61 L) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | rescue (rule changed by design) |
| No generic overlay / no shared idea across files | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| A packing matches how C is read | ✓ raw HDR | ✓ (no C read) | ✓ HDR+depth | ✓ display | ✓ display | ✓ display | ✓ fixed to display | ✓ raw state |
| `updatedParams` byte-equal to HEAD (checked vs `git show HEAD:`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Springs / ripples added | none | none | none | none | none | none | none | none |
| extraBuffer use | none | none | comment only | none | none | comment only | comment only | comment only (no code use) |
| Naga (coordinator re-run) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Sampler read of C / hard-coded alpha 1.0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| All 4 `zoom_params` components read | ✓ | ✓ | ✓ | ✓ (via `zparams`) | ✓ | ✓ | ✓ | ✓ |

**Verdict: PASS for all 8, with the open items below.**

## Coordinator corrections
- `gen-vortex-cathedral.json`: the agent added non-contract feature tags (`arch-gated-shafts`, `stained-glass-tint`, `counter-rotating-vault`). Stripped; kept only `upgraded-rgba`, `mouse-driven`, and added `audio-reactive` (the shader reads `plasmaBuffer[0].xyz`; HEAD's JSON simply omitted it).
- Feature-tag review of the other JSONs: only true contract tags were added (`upgraded-rgba`, `audio-reactive`, `mouse-driven`). `gen-stellar-web-loom.json` also received one description sentence naming the new ideas (kept; no schema change).

## Independent verification performed
- Naga on all 8 + `wgsl_precommit_gate.py` (8/8, bindgroup compatible).
- `audit:extrabuffer`: 0 new violations. `audit:dead-sliders`: scanned **0** definitions (known blind spot — JSON carries only `updatedParams`), so verified by hand: all four `zoom_params` components are read in each shader. This proves the reads exist, not that each slider changes the picture visibly.
- Reef Density: `branchCount = clamp(i32(floor(reefDensity*9+0.5)),3,9)`; default 0.5 → `reefDensity` 0.55 → `floor(5.45)` = **5**; zparams.x 0.45–0.56 also gives 5. Coral loop is `const 9` with `if (i >= branchCount) { break; }`.
- Physarum numpy gate re-run by the coordinator: results reproduced the agent's table exactly (9 cases, 1500 steps, N=128). All alive, none saturated, none frozen. Weak cases: `Trail Decay = 1` (near-uniform trail) and `Sensor Distance = 0` (giant component 0.66). **The port is not the WGSL** — the WGSL rule was reviewed only via the agent's "mirrors line for line" claim plus naga; not executed.
- `generate_shader_lists.js` ran; Jest: 101 suites pass, 6 fail — the same 6 pre-existing WASM-bridge `.js` import suites (`Cannot find module './bridge/api.js'` / `'./state.js'`), nothing from this batch. `SKIP_WASM_BUILD=1 npm run build`: exit 0.

## Open items (need real-GPU eyes)
1. singularity-forge beaming scale `0.7·D³·g²` (clamp 3.0) is untuned.
2. ouroboros ACES exposure 0.8 and default-look brightness.
3. cathedral counter-rotating vault ring vs sanctum visibility at defaults; per-step god-ray cost (+atan2/sin/smoothstep ×2 passes).
4. phase-weave cost (~1.4–1.6× HEAD, agent estimate, not measured); web-loom `pluck()` ×3 per march step.
5. physarum vein look at saved sliders, especially Trail Decay = 1.
6. Look-change list is in NOTES.md (physarum, ouroboros, web-loom, tectonic, cathedral).

## Shared-tree state
Uncommitted, per precedent. `reports/*` were already dirty from other sessions before this batch; the gates rewrote them again (diff hash changed, 5 files) — not reverted, since a `git checkout -- reports/` would destroy other sessions' changes. `MEMORY.md` / `USER.md` / regenerated lists (`public/shader-lists/generative.json`, search index, aliases) contain other sessions' hunks too; a commit must stage only this batch's 8 WGSL + 8 JSON + this directory and splice the shared files (see memory `project-shared-worktree-batches`).
