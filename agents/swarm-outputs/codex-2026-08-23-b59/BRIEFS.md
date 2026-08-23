# Shader Upgrade Batch 59 — Liquid Premium Motion

## Scope

Upgrade ten single-pass liquid shaders without changing runtime APIs, bindings,
uniform layout, saved parameter arrays, feedback copy order, or renderer code.
The cohort is Liquid Jelly, Jelly Fluid, Lens, Magnetic Ferro EM, Metal
Prismatic, Mirror, Oil, Oil Iridescence, Prism, and Rainbow.

## Shared contract

- Canonical bindings 0–12, `@workgroup_size(16, 16, 1)`, and output bounds guard.
- `dataTextureB` and `extraBuffer` declared for layout compatibility but unused.
- `config.y` is only a click/ripple count, capped at 50; audio is
  `plasmaBuffer[0].xyz`.
- Pointer and click distances are aspect-correct. Negative and expired click ages
  are rejected. Held input has a stronger local effect than hover.
- `rgba32float` C feedback uses bounded `textureLoad`; source/depth UVs are
  clamped and state/HDR/alpha ranges are bounded.
- Every effect has multiple continuous time-driven motion mechanisms and avoids
  time hashes or frame-dependent strobing.

## Performance split

Jelly Fluid, Magnetic Ferro EM, and Oil Iridescence receive the heavier bounded
state/neighbor sampling budget. The remaining seven stay efficient single-pass
image effects. Real-GPU 1080p profiling is a handoff requirement for the three
heavier shaders.
