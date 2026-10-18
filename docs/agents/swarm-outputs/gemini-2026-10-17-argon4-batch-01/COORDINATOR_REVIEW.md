# Coordinator Review — Gemini Argon4 (`argon4/batch-01`, 2026-10-17)

Contract checklist per [`docs/SHADER_UPGRADE_BATCH.md`](../../../SHADER_UPGRADE_BATCH.md) §9:

## Per-Shader Checklist Verification

| Shader ID | Idea Card Pre-Written | Ideas Pointable in WGSL | KEEP VERBATIM Held | Not Boilerplate-Heavy | Distinct Native Ideas | A/C Packing Honest | Saved `params` Byte-Exact | Native Springs/Ripples Only | Naga + Audits Pass | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| `glass_refraction_alpha` | Yes | `exitNormal`, `tirCorona`, `blobNeckStress`, `stressFringe` | Yes | Yes | Exit TIR corona + neck photoelastic birefringence | Display RGBA (`B` kept) | Yes (4/4) | Click pressure fronts kept | PASS | **PASS** |
| `gen-holographic-data-core` | Yes | `braggLamella`, `braggStrata`, `ghostShift`, `ghostHistory` | Yes | Yes | Inner-core Bragg memory strata + Pepper's-ghost parallax | Linear HDR display RGBA | Yes (4/4) | Pointer beam + click data rings kept | PASS | **PASS** |
| `gen-minimal-surface-soap-iridescence` | Yes | `asymU`, `asymV`, `asymptoticWeb`, `airyOrder2`, `foldProximity` | Yes | Yes | Bonnet asymptotic web + multi-bounce Airy finesse | ACES display RGBA | Yes (4/4) | Culick click-rupture holes kept | PASS | **PASS** |
| `liquid_crystal_birefringence` | Yes | `walkOff`, `bgO`, `bgE`, `conoscopicMask`, `isogyreArm`, `melatopeRing` | Yes | Yes | Extraordinary-ray walk-off + conoscopic Maltese cross | ACES display RGBA | Yes (4/4) | Existing `[133..134]` defect spring kept | PASS | **PASS** |
| `photonic-caustics-iridescence` | Yes | `foldBand`, `airySupernumerary`, `bouncePix`, `subsurfaceBounce` | Yes | Yes | Catastrophe-optics Airy fringes + subsurface depth bounce | ACES display RGBA | Yes (4/4) | Existing `[133..138]` light spring kept | PASS | **PASS** |
| `iridescent-oil-slick` | Yes | `lensDome`, `lensMoat`, `surfactantCollar`, `surfactantThin`, `advectedColor` | Yes | Yes | Ostwald oil microlenses + click surfactant fronts & RGB advection | Pre-ACES RGB + `4.0 + push` in `A.a` | Yes (4/4) | Surfactant click rings native | PASS | **PASS** |
| `gen-celestial-prism-orchid` | Yes | `labellumMask`, `chevronStriae`, `floralCaustic`, `polliniaArc` | Yes | Yes | Labellum UV-to-gold chevrons + 5-fold floral caustics & pollinia tether | ACES display RGBA | Yes (4/4) | Existing `[133..138]` pollinator spring kept | PASS | **PASS** |
| `gen-ethereal-glass-flora-terrarium` | Yes | `pinnateVeins`, `stomataPores`, `domeMullion`, `domeFresnel`, `mistRing` | Yes | Yes | Geodesic dome mullions & mist rings + pinnate leaf venation & stomata | ACES display RGBA | Yes (4/4) | Acoustic mist rings on glass dome | PASS | **PASS** |
| `gen-liquid-rainbow-glass` | Yes | `gatherWarp`, `gatherRim`, `caneStriae`, `caneDisp`, `dichroicTransmit`, `dichroicReflect` | Yes | Yes | Hand-blown murrine striae + dichroic shift & molten gathers | Display-history RGBA | Yes (`x-meta` exact) | Molten glass gathers on click | PASS | **PASS** |
| `gen-prismatic-cyber-aether-void-kitsune` | Yes | `d_orb`, `eyeSlit`, `browCrest`, `dispBeam`, `prevWake` | Yes | Yes | Levitating Hoshi-no-tama orb & kabuki visor + Cauchy shard beams & C wake | ACES display RGBA | Yes (4/4) | Fox-fire click rings kept | PASS | **PASS** |

## Summary
- **10 / 10 shaders passed** all creative and structural requirements.
- **4 / 4 pasted headers migrated** to `#include "_prelude.wgsl"` via `scripts/migrate_to_prelude.py` (`glass_refraction_alpha`, `gen-minimal-surface-soap-iridescence`, `liquid_crystal_birefringence`, `photonic-caustics-iridescence`); the other 6 were already on `_prelude.wgsl`.
- **Real-GPU visual QA**: External (Cloud VM has no hardware GPU).
