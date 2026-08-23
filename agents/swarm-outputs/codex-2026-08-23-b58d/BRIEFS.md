# Batch 58D briefs — 2026-08-23 — SPECTRAL AND DATAMOSH UPGRADE

Batch 58D upgrades ten existing image, spectral, and datamosh effects to the
canonical 13-binding compute contract without allocating tracker numbers or
changing renderer, bind-group, graph, TypeScript API, or dependency behavior.

| Shader | A ownership | Upgrade focus |
|---|---|---|
| `spectral-bleed-confinement` | display RGBA | Sprung focus, bounded confinement fronts, three-band audio, exact afterglow |
| `spectral-flow-structure` | display RGBA | Truthful exact-history smoothing, bounded turbulence, audio LIC/coherency |
| `spectral-glitch-sort` | display RGBA | Guarded single-writer spring, FFT block voices, exact tear trails |
| `spectral-smear` | display RGBA | Integer history advection, click paint blooms, decayed spectral persistence |
| `spectral-vortex` | phase/curl/energy state | Phase removed from depth and packed with curl state in A |
| `spectral-waves` | premultiplied display RGBA | Sprung origin retained, exact caustic persistence, corrected FFT reads |
| `spectrogram-displace` | display RGBA | Live plasma/FFT spectrogram, 16x16 workgroup, exact scrolling history |
| `spectrum-bleed` | display RGBA | Guarded spring, exact ink persistence, semantic alpha |
| `data-moshing` | offset/confidence/age state | Raw offset ownership, sprung scrub, bounded click corruption |
| `datamosh` | motion/age/strength state | Sole A state, current-source prediction, ineffective B path removed |

## Shared contract

- Canonical bindings 0–12 and authoritative `Uniforms` layout.
- `@workgroup_size(16, 16, 1)` with output bounds guards.
- Exact clamped `textureLoad` for every `dataTextureC` history/state read.
- A written for every pixel; B intentionally unwritten.
- `plasmaBuffer[0].xyz` for bands and read-only `extraBuffer[5..132]` for FFT detail.
- Spring state only at guarded `[133..138]`, persisted by invocation `(0,0)`.
- Ripple loops use the live count capped with `min(u32(u.config.y), 50u)` and finite windows.
- Canonical `acesToneMap`, semantic alpha, and source-depth pass-through.
- Source `params` arrays preserved exactly; indexed `updatedParams` aligned by slot.
