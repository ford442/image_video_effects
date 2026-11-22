# sonnet/batch-54 — COMMON (read first)

Worktree /root/iv-sonnet-batch-54 (branch sonnet/batch-54). Do NOT touch git, do NOT run npm build / generate_shader_lists / upgrades:record (coordinator does). No pkill. Other sessions share the box.

## Engine semantics (framePlan.ts)
- Linear chain (liquid pairs, pyramid trio): passes back-to-back, SAME readTexture, no copies between; B->C then A->C after the whole slot. Pass 2 sees pass 1 state ONE FRAME LATE.
- Foam is Tier C graph: A->C before pass 2, B->C before pass 3 (same frame).
- ACES only on the FINAL pass display RGB; intermediate raw state / passthrough is never tone-mapped.
- u.config.y = rippleCount (NOT intensity). zoom_config = (time, mouseX, mouseY, mouseDown).

## Rules
- Saved params byte-exact (JSON untouched by forks; coordinator aligns JSON). All 4 zoom_params stay read.
- Keep dataTextureB writes (foam-2, pyramid-1) — documented hand-offs. pyramid-2/3 are NOT modified.
- Idea Card per shader in BRIEFS-<fork>.md BEFORE WGSL. Mark ideas in WGSL as `// ── Idea N: name` . Header: Upgraded: 2026-11-22, Ideas:, A packing:.
- Rescues (HEAD defects) are reported separately from ideas in NOTES-<fork>.md.
- textureLoad with clamped integer coords for every dataTextureC read.
- Add plasmaBuffer[0].xyz only where it is physically native; tag `audio-reactive` only if it modulates the picture.
- Gate each file: python3 scripts/wgsl_precommit_gate.py --files public/shaders/<id>.wgsl ; and `npm run verify:naga-wasm -- --files ...` if available.
- Cost cap <=1.3x HEAD (SwiftShader, min-of-drained-frames, interleaved); report honestly if a rescue exceeds it.
- Harness: agents/mrchain.mjs (see header). Ripple 3rd value = ABSOLUTE start time. DEPTH=const:0 for whole-frame liquid. Test A16=1 too.
