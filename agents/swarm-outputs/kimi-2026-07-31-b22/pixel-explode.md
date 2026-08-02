# Swarm Output: pixel-explode (Batch 22 — Algorithmist)

## Lines
- Before: 109 → After: 161 (+52, within target 159–199)

## Priority 1 — All 4 dead sliders wired (u.zoom_params was never read)
| Slider | Param (id/name/default) | WGSL role | Default-look check (0.5) |
|---|---|---|---|
| x | param1 / Intensity / 0.5 | `explosion_force = mix(0.0, 0.16, x) * (1.0 + mids * 0.3)` | 0.08 — bit-exact ✓ |
| y | param2 / Speed / 0.5 | NEW wobble: `offset += vec2(sin(wphase), sin(wphase+2.0944)) * 0.01 * total_strength`, `wphase = time * mix(0,4,y) + cellHash*6.28` | speed 2.0 ✓ (adds motion; shader previously had zero time animation — brief-sanctioned) |
| z | param3 / Scale / 0.5 | `grid_size = mix(16.0, 64.0, z)` | 40.0 — bit-exact ✓ |
| w | param4 / Detail / 0.5 | `range = clamp(i32(mix(2.0, 10.0, w)), 2, 10)` — now the neighbor-loop bound (WGSL var bound) | 6 — bit-exact ✓ |

Defaults verified numerically (python mix/trunc check): force 0.08, wobble 2.0, grid 40.0, range 6.
At defaults the static look is identical to the old shader; the only new default-time behavior is the gentle wobble (y wiring) and audio-driven crackle, both mandated by the brief.

## Techniques added
- **Per-cell hash** `fract(sin(dot(neighbor_cell, vec2(12.9898, 78.233))) * 43758.5453)` — stable wobble phase + treble bin selector.
- **Treble crackle** (dead-treble wiring): inside the z-buffer hit, `final_color += vec4(vec3(plasmaBuffer[(u32(cellHash*8.0) % 8u) + 1u].x * total_strength * 0.3), 0.0)` — blast-edge cells sparkle with the spectrum.
- **Click detonations**: ripple loop guarded `min(u32(u.config.y), 50u)`; each live ripple (`age > 0 && age < 1.5`, `age = time - ripple.z`) acts as a decaying second explosion center using the same `smoothstep(explosion_radius, 0.0, cdist)` strength form with force `* exp(-age * 2.5)`; pushes `offset` and feeds `total_strength`.
- `total_strength = clamp(strength + click_strength, 0, 1)` drives wobble amplitude and crackle so clicks also wobble/sparkle.
- Engine uniform-truth comment block added above the Uniforms struct.

## VERBATIM preserved
- Branchless z-buffer coverage: `inParticle = select(0.0, 1.0, ...)` + `if (inParticle > 0.5 && z_depth < closest_z)` / `closest_z = z_depth` ✓
- Particle scale-up: `let scale = 1.0 + strength * 2.0;` ✓ (kept on mouse `strength` exactly)
- local_uv sub-sampling: `local_uv = (uv - new_center) / max(particle_half_size * 2.0, vec2(0.0001)) + 0.5;` + clamped `tex_uv` + `textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0)` ✓
- Dark-bg branchless fallback: `isBg = select(...)` + `mix(final_color, vec4(0.05,0.05,0.1,1.0), isBg)` ✓
- Immutable 13-binding layout; `@workgroup_size(16, 16, 1)`; writeTexture/writeDepthTexture/dataTextureA written every frame; dataTextureA stays DISPLAY color; no binding 13.

## JSON changes
- `shader_definitions/interactive-mouse/pixel-explode.json`: added ONLY `updatedParams` (index 0–3, same names/defaults/min/max/step as `params`) and `updated: true`. ids/names/defaults untouched — saved-preset contract kept. JSON validated with `json.load`.

## Deviations
- Wobble uses two phase-shifted sines (`+2.0944`) instead of a scalar replicated `vec2(sin(...))` so drift is 2D rather than purely diagonal; amplitude/speed/phase formulas exactly per brief.
- `offset` changed `let` → `var` (needed for wobble/click accumulation); not on the VERBATIM list.
- extraBuffer declared (layout contract) but never read/written — no [133..255] usage needed.

## Gate
`python3 scripts/wgsl_precommit_gate.py --files public/shaders/pixel-explode.wgsl`
→ **GREEN**: 1 passed / 0 failed, naga OK, bindgroup compatible, 0 warnings, 0 extraBuffer violations.
