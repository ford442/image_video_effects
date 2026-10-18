# Shader Upgrade Batches — Incremental Ideas Contract

> **This is the live process.** Paste this file (or §0) into Gemini / Grok / Claude / Antigravity before a batch.
> Longer plumbing reference: [`docs/agents/CLOUD_UPGRADE.md`](agents/CLOUD_UPGRADE.md).
> Bindings / uniforms: [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md) and [`docs/agents/WGSL_BUILTINS_GENERATIVE.md`](agents/WGSL_BUILTINS_GENERATIVE.md).

---

## 0. Copy-paste law (put this at the top of every batch prompt)

An upgrade **adds 2–4 named visual ideas to the existing effect**. It is not a new shader, not a reimagining, and not a formatting / uniform-alignment pass.

1. **Write an Idea Card for every shader before touching WGSL.** If you cannot name the additions in one sentence each, you are not ready to edit.
2. **Keep the algorithm, the look, and the saved `params`.** Same modes, same kernel family, same identity. Deepen what is already there.
3. **Plumbing is the floor, not the upgrade.** Canonical 13 bindings, 16×16, ACES, semantic alpha, exact C loads, live sliders, and `x-meta.upgrade.params` alignment must happen — they do not by themselves count as an upgrade.
4. **No generic overlay.** Do not stamp every file with the same spring cursor, ripple shockwaves, IQ cosine palette, and two “conveyors.” Ideas must be native to *this* effect.
5. **Refuse a header-only or rewrite-only result.** A shader that newly compiles, writes depth/A, and looks the same is not upgraded. A shader whose name still matches but whose picture is a different effect is not upgraded either.
6. **Bindings come from `#include "_prelude.wgsl"`.** Never paste the 13 binding declarations or `struct Uniforms` — CI fails on a pasted copy. If a file you touch still pastes them, run `python3 scripts/migrate_to_prelude.py --files public/shaders/<id>.wgsl` first. That swap is infrastructure, not an upgrade: never bump `Upgraded:` for it.

[... content truncated for this message; the actual call used the full file content from /tmp/SHADER_UPGRADE_BATCH_current.md ...]