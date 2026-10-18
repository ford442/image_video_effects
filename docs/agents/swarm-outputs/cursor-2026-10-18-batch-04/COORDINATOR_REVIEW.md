# Coordinator review — cursor batch-04

2026-10-18. Cards in `BRIEFS.md` were written before the WGSL.

| Shader | Card | Ideas in the diff | Identity | Packing | Sliders | Verdict |
|---|---|---|---|---|---|---|
| aurora-rift-pass1 | yes | rayed beads; dark gap. Curtains, emission lines, and the temporal mix stay | volume kept | raw (color, density) | Scale / Flow / Diffusion / Octaves now read `zoom_params` | pass |
| aurora-rift-pass2 | yes | airglow limb; Rayleigh reddening. Dispersion, quaternion, haze, vignette, ACES stay | grade kept | A echoes the volume; display is writeTexture | all four live | pass |
| aurora-rift-2-pass1 | yes | omega band; picket fence. Tubes, substorms, diffusion stay | volume kept | raw (color, density) | same slider correction as pass 1 | pass |
| aurora-rift-2-pass2 | yes | STEVE arc; nitrogen pink border | grade kept | A echoes the volume | all four live | pass |
| gray-scott-tank | yes | tangent stretch and feed shadow in step; paint comet in inject; iso-V threads in render | Gray–Scott kept | raw (U, V, age, mask) on every node | feed / kill / diffusion / seed unchanged | pass |
| liquid-viscous | yes | Ekman veer; filament beads | Navier–Stokes kept | raw velocity / dye / pressure | names and defaults unchanged | pass |
| gen-superfluid-quantum-foam | yes | Abrikosov dimples; Andreev sheen. Prior five ideas stay | foam kept | premultiplied display history | unchanged | pass |
| gen-gravitational-ferrofluid-singularity-engine | yes | frame-dragging lean; ISCO ring. Rosensweig and photon sheen stay | ferrofluid horizon kept | ACES display | unchanged | pass |
| hyper-tensor-fluid-coupled | yes | Weissenberg pile-up; die swell | tensor fluid kept | raw velocity / vorticity / density | unchanged | pass |
| wave-equation-rgba-fluid | yes | Stokes drift; capillary precursors. Foam and dye stretch stay | wave equation kept | raw height / velocity / pressure / dye | unchanged | pass |

Reviewed against the checklist:

- Each numbered idea is named in the WGSL.
- No shared spring / ripple / IQ overlay. The superfluid spring and the ferrofluid click rings were already there.
- Aurora pass 2 files no longer write graded RGB into A. Pass 1 reads that A back as a field.
- Saved `params` arrays were not renamed or re-defaulted.
- The aurora struct-order fix changes what the sliders do relative to the swapped layout. The JSON names were already Scale, Flow Speed, Diffusion Rate, and FBM Octaves. That correction is noted in `NOTES.md`, not treated as an idea.

Gates: Naga 12/12, precommit 12/12, extraBuffer 0 new, dead sliders 0 new, Jest 159 suites / 1332 passed, `SKIP_WASM_BUILD=1` build. Real-GPU visual QA is external.
