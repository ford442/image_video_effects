# Coordinator review — cursor/batch-10 (2026-10-26)

Cards were written before the WGSL. Each new idea in `BRIEFS.md` has a `// ── Idea:` comment in that shader. Earlier ideas were left in place.

| Shader | Verdict | Formula rows | Notes |
|---|---|---|---|
| magnetic-pixels | pass | none | Equator uses `cosTheta`. Grains run along the moment. Phase texel untouched. |
| liquid-fast | pass | none | Shear is a difference of `streamVelocity`. Tail uses the existing pointer velocity. |
| luma-magnetism | pass | none | Pile is `\|∇luma\|`. Seam is gradient against the pointer term. RK2 unchanged. |
| luma-melt-interactive | pass | surface tension (§12.2D) | Bead is the leading side of the existing packet. Crust uses `hereTemp - temp`. |
| neon-fluid-warp | pass | speed-thinning (§12.2C) | Rim width is `w0/(1+k\|wake\|)`. Crest is the existing jet sine. |
| slime-drip | pass | surface tension (§12.2D) | Second file on that row. Toe and neck read neighbor drips from C.r. |
| liquid-rgb | pass | none | Eye is r = 0.2 on the existing four centers. Memory split is zero when separation is zero. |
| liquid-rainbow | pass | deep-water dispersion (§12.2D) | Middle wave keeps its authored speed. Dispersion slider still chromatic. |
| ink-diffusion | pass | 9-point Laplacian (§12.2D) | Backrun only while the pointer is up. Nijimi kept. |
| liquid-displacement | pass | shallow-water continuity (§12.2D) | Confinement and streaks kept. Bore is velocity into `heightGrad`. |
| rgb-fluid | pass | none | Wavelength split is the file's own 650/550/450 model. Beer-Lambert is display-only. C is `textureLoad`. |
| ink-marbling | pass | none | Gall scales the existing diffusion. Stone uses the ring the Jaffer loop already computes. |

Formula cap: surface tension on two files. Every other row is on one file. No MacCormack. No shared spring, ripple stamp, or new IQ palette.

KEEP VERBATIM holds: kernels, param roles, and A packing match the cards. Saved `params` were not edited.

Naga + precommit on these 12 files passed. Dead-slider and extraBuffer audits on these files reported 0 new findings. Real-GPU visual QA was not run.
