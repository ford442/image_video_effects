# Coordinator review — cursor/batch-58

Cards were written in `BRIEFS.md` before the WGSL. Each numbered idea has a `// ── Idea` marker.

| File | Verdict | Why |
|---|---|---|
| dla-walkers | pass | Tip gate, facet fold, and speed reach sit on the existing stick/step. Workgroup 64×1×1. No extraBuffer. Constants of the walk are unchanged. |
| dla-render | pass | Tip glow, facet glint, and age rings use fields the walkers already store. ACES is display-only. Seeds kept. |
| physarum-agents-diffuse | pass | 3×3 and TRAIL_CAP kept. Anisotropy and fresh-front sparing use the trail and the deposit time. |
| physarum-agents-step | pass | FOOD_W / WANDER / DEP0 / TRAIL_CAP unchanged. Crowded U-turn and satiation still write one value per texel. |
| chromatographic-diffuse | pass | Per-channel viscosities kept. Saturation and heat scale that same step. |
| chromatographic-interact | pass | Mean drag and treble separation kept. Competition and the unsharp use the dye already loaded. |
| chromatographic-phase | pass | Evaporation amount, condensation, and the blue vapor tint kept. Volatility and latent heat ride that amount. |
| sph-fluid-density | pass | Named constants, poly6, curl, seed, and aux packing kept. Core kernel and surface vorticity are extra terms. |
| sph-fluid-force | pass | Solver terms and the stamp channels kept. Tensile term is beside pressure. Spray changes the stamp's speed channel only. |
| gen-luminescent-chrono-fluid-astrolabe | pass | Vernier and magnitudes extend the limb and the rete. FFT bins removed. Spring stays in 133–138. Named params copied from x-meta. |
| gen-sonoluminescent-chrono-geode-matrix | pass | Nodes and the recombination tail use the cavity radius and the existing C trail. FFT bins removed. Named params copied. |
| gen-lichtenberg-storm | pass | Carbon track and streamer hairs use charge and corona already computed. FFT bins removed. Spring stays in 133–138. Named params copied. |
| gen-prismatic-void-weaver-ouroboros | pass | Occlusion and trailing shade use the jaw angle and the keel side already computed. FFT bins removed. Named params copied. |
| gen-sentient-cyber-chrono-void-serpent | pass | `fn aces` and an exact C load. Phosphor mix is after the tone map. Spectral node is on the existing ring band. Named params copied. |
| matrix_digital_rain | pass | Phosphor and the decode latch read last frame's display. `extraBuffer[0]` is gone. Saved params untouched. |

Formula check: no §12.2 row was added. No file shares a spring, shockwave, or palette overlay with the next.

Saved params on definitions that already had them were not edited. `dla-crystals` gained `upgraded-rgba` because the render pass now tone-maps the display.

Real-GPU visual QA: external.
