# Hybrid leftover ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `hyb-hex-voronoi-distort` | hex_scale / voronoi_density / distort_amount / effect_mix; nearestHexCenter; mix(uv, hexCenter) | `dist2` F2−F1 `crack`; `mortar` from hexEdgeDist | ACES display RGBA. Mouse UV 0–1 (killed `/ dims`). |
| `hyb-chromatic-circuit` | grid_scale / trace_width / chroma_spread / effect_mix; chroma along hex grad; image-edge boost | `neighborGate` both ends; packet at `h` vs `packetHead` | ACES display RGBA (HEAD never wrote A) |
| `hyb-neural-voronoi-feedback` | density / drift / dust / mix; fbm drift; dust; existing iridescence | `textureLoad` C along drift; F2 `synapse` | ACES display RGBA. Write A so C is color. |
| `hybrid-particle-fluid` | particle_count / flow_speed / trails / glow_size; curlNoise; golden-ratio seeds | `textureLoad` C; two LIC taps along velocity | Display RGB in A; ACES writeTexture. Particle loop count unchanged. |
| `hybrid-magnetic-field` | field_strength / line_density / trails / distortion; 1/r³; orbiting source2; FBM | source2 **negative** strength; exact-C LIC | Display RGB in A; ACES writeTexture. Killed `config.y` as audio. |
| `hybrid-cyber-organic` | circuit_density / growth / glow / chaos; hex; FBM growth; tendrils | `occupy = max(growthLive, C.r * fade)`; `srcLuma` seed | raw occupancy in A.r. ACES writeTexture only. |
| `spec-hypercube-projection` | rot_xw / rot_yz / edge_glow / face_opacity; 16 verts; one-coordinate edges; held extra rot | `wEdge` thicker/cooler; photo at closest-edge `h` | ACES display RGBA (HEAD packed edgeColor/edgeDepth, never read C) |
| `hex-circuit` | grid_size / glow / pulse_speed / edge_sensitivity; hex; imgEdge; mouse sin-ring | via at nucleus; `persist` from C.a | ACES display RGBA (HEAD packed telemetry) |
| `neon-poly-grid` | grid-scale / line-width / glow / decay; extraBuffer[133..138] spring; click rings; A.r trail | dual-lattice `vertex`; `cellFill` | Keep A.r trail. Exact C load. ACES writeTexture. Spring kept. |
| `neon-light` | base_temperature / edge_heating / emissive_gain / thermal_fog; blackbody; Sobel; Schlick; mouseHot | `textureLoad` phosphor; Sobel along tangent | raw phosphor in A. ACES writeTexture. |

No new extraBuffer springs. `neon-poly-grid` spring kept. Saved `params` unchanged; `updatedParams` added by index.

Did **not** take kaleido hybrids, Batch 56/58E/61 overlays, `hybrid-sdf-plasma` / `hybrid-chromatic-liquid` (ink/halftone kernel ≠ named effect), or `hybrid-fractal-feedback`.
