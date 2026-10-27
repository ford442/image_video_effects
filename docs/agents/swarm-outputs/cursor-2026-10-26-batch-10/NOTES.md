# Cursor batch-10 — notes

2026-10-26. Cards in `BRIEFS.md` were written before the WGSL edits.

Saved `params` were not renamed or re-defaulted. `ink-diffusion` and `rgb-fluid` had pasted headers migrated to `#include "_prelude.wgsl"`. That swap is not the upgrade.

## magnetic-pixels

Kept the dipole, flux isolines, N/S lobes, pole glow, and the phase texel at (0,0).

Added a dark equator where `m·r` crosses zero, and filing gaps along the moment. Metallic still scales sheen and now the grain pitch. No §12.2 row.

## liquid-fast

Kept the Hamiltonian stream, convective shear, the spring in `extraBuffer[133..138]`, the drag vortex, and the ripple packets.

Added a shear glint from finite differences of `streamVelocity`, and a narrow jet behind the existing pointer velocity, in the same space as the inertial jet. No §12.2 row.

## luma-magnetism

Kept bidirectional RK2 streamlines, clump, bare caps, and the held luma-signed pole. The RK2 step cap is unchanged.

Added filament weight from `|∇luma|` and a break where that gradient opposes the pointer term. No §12.2 row.

## luma-melt-interactive

Kept the melt mask, runners, temperature in A.a, and the ledge stall. A stays linear melt RGB plus temperature.

Added a bead on the leading side of the drip packet (§12.2D) and a crust that pulls cooled pixels toward luma.

## neon-fluid-warp

Kept the sentinel texels, the wake, the meniscus, and the viscous clock.

The rim width is now `w0 / (1 + k·|wake|)` (§12.2C). The curl jet's sine peak is a bright thread. No new palette.

## slime-drip

Kept the anisotropic stretch, the C.r hang, the wipe, and the raw packing.

Added a toe bead where the drip exceeds the pixel below (§12.2D) and a viscosity-weighted neck pinch from the horizontal drip ridge.

## liquid-rgb

Kept the four complex vortices, the per-channel paths, and Beer-Lambert absorption. A stays ACES display RGBA.

Added an eye wall at r = 0.2 on each existing center, and a history mix that lets red lead and blue linger with the separation slider. At separation 0 the three mixes match.

## liquid-rainbow

Kept the three Gerstner waves, the braid, the film, and the spring. The dispersion slider still owns the chromatic split.

Phase speed now scales as `1/sqrt(k)`, normalized so the middle wave keeps its authored speed (§12.2D). Crests of the Gerstner height sum brighten; troughs darken.

## ink-diffusion

Kept fiber steering, the vorticity kick, the brush, and nijimi. A stays ink, velocity, alpha.

The diffusion Laplacian is 9-point at the same spread coefficient (§12.2D). While the pointer is up, the body pales and the wet rim darkens.

## liquid-displacement

Kept confinement, the streaks, and the spring. A stays velocity, height, activity.

The height step multiplies divergence by the stored height (§12.2D). A bore lip lights where velocity runs into a steep slope.

## rgb-fluid

Kept the sine flow, the mouse push, the viscosity persistence, the color-shift rotation, and the 650/550/450 nm alphas.

Red and blue now advect on either side of the shared path, scaled by color shift. Beer-Lambert tints `writeTexture` only. A stores the pre-absorption pigment so the law does not compound. History reads are four `textureLoad`s, not a filtering sample of `dataTextureC`. ACES is on the display.

## ink-marbling

Kept the rake, the Jaffer map, and the spring. A stays pigment plus thickness.

Diffusion falls where the pigment gradient is steep. The existing drop ring adds thickness and darkens that front.

## Floor

No saved param edits. No new feature tags: the files that claim `upgraded-rgba` or `audio-reactive` already did, and the new audio reads were already there. `rgb-fluid` now actually tone-maps the display it was already tagged for.

## Gates

Naga 12/12. Precommit 12/12, extraBuffer violations 0 on these files, pasted headers 0. Dead sliders on these 12: 0 new. Vitest: 169 files, 1435 passed, 1 skipped. `SKIP_WASM_BUILD=1 npm run build` succeeded. Ledger recorded these 12 ids.

Real-GPU visual QA is external. This VM has no hardware GPU.
