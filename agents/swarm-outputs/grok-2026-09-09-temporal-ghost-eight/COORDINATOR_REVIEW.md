# Coordinator review — Temporal ghost / lag eight

Checklist vs `docs/SHADER_UPGRADE_BATCH.md` §9.

| Shader | Card before WGSL | Ideas in diff | KEEP VERBATIM | Not overlay | A packing | Params exact | Springs native | Naga |
|---|---|---|---|---|---|---|---|---|
| time-lag-map | yes | luma-keyed delay; motion smear | 5 maps kept | yes | history RGB | yes | existing ripples | pass |
| temporal-rift | yes | arrival delay; C ghost shear | yes | yes | nextHist | yes | existing [133..138] | pass |
| phantom-lag-history | yes | age-tint; luma persist | A.a luma kept | yes | RGB+luma A | yes | none | pass |
| hyb-temporal-fbm-ghost | yes | C channel lag; source-tied ghost | warp kept | no new IQ | display RGBA | yes | none | pass |
| spectral-slit-scan | yes | wavelength stagger; luma-hold | curves kept | yes | display RGBA | yes | none | pass |
| rgb-delay-brush | yes | bristle; wet C | Beer-Lambert kept | yes | delayed RGB | yes | existing [133..138] | pass |
| green-tracer | yes | phosphor C; edge trail | 4 JSON roles | yes | trail RGB | yes | none | pass |
| phase-shift | yes | angular period; dist phase | 5-layer speeds | not RGB-split clone | display RGBA | yes | stopped [0]/[10] | pass |

green-tracer Uniforms order canonicalized; sliders still trail/glow/tint/noise.

Verdict: **pass** (structural). Real-GPU visual QA external.
