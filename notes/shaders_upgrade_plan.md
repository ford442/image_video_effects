# Shader Upgrade Plan - File Size Analysis

**Generated:** March 2026  
**Total Shaders:** 593  
**Total Size:** 2,826,772 bytes (~2.76 MB)  
**Average Size:** 4,766 bytes

---

## Executive Summary

This document catalogs all WGSL shaders by file size to prioritize upgrade efforts. **Smaller shaders are recommended for first priority** as they represent simpler codebases that can be updated more quickly and with lower risk.

### Why Upgrade Smaller Shaders First?
- **Lower complexity** = Easier to understand and refactor
- **Faster iteration** = Quick validation of upgrade patterns
- **Reduced risk** = Smaller surface area for bugs
- **Template building** = Establish patterns that can be applied to larger shaders

---

## Size Distribution

| Tier | Size Range | Count | % of Total | Priority |
|------|------------|-------|------------|----------|
| **Tiny** | < 2 KB | 9 | 1.5% | 🔴 **CRITICAL - FIRST WAVE** |
| **Small** | 2-3 KB | 52 | 8.8% | 🟠 **HIGH - SECOND WAVE** |
| **Medium-Small** | 3-4 KB | 207 | 34.9% | 🟡 **MEDIUM - THIRD WAVE** |
| **Medium** | 4-5 KB | 171 | 28.8% | 🟢 **LOWER - FOURTH WAVE** |
| **Medium-Large** | 5-6 KB | 58 | 9.8% | 🔵 **LOW - FIFTH WAVE** |
| **Large** | 6-8 KB | 44 | 7.4% | ⚪ **BACKLOG** |
| **X-Large** | 8-12 KB | 37 | 6.2% | ⚪ **BACKLOG** |
| **XX-Large** | 12-16 KB | 12 | 2.0% | ⚫ **DEFERRED** |
| **Huge** | > 16 KB | 3 | 0.5% | ⚫ **DEFERRED** |

---

## 🔴 TIER 1: TINY SHADERS (< 2KB) - FIRST WAVE

**Count: 9 shaders | Total: ~15 KB**

These are the simplest shaders - excellent candidates for initial upgrade pilots.

| Rank | Shader | Size (B) | Est. Lines | Notes |
|------|--------|----------|------------|-------|
| 1 | `texture` | 719 | ~25 | Render pass shader - minimal |
| 2 | `gen_orb` | 1,402 | ~45 | Simple generative orb |
| 3 | `gen_grokcf_interference` | 1,535 | ~50 | Interference pattern |
| 4 | `gen_grid` | 1,594 | ~50 | Grid pattern |
| 5 | `gen_grokcf_voronoi` | 1,630 | ~55 | Voronoi cells |
| 6 | `gen_grok41_plasma` | 1,648 | ~55 | Plasma effect |
| 7 | `galaxy` | 1,682 | ~55 | Galaxy shader |
| 8 | `gen_trails` | 1,878 | ~60 | Particle trails |
| 9 | `gen_grok41_mandelbrot` | 1,883 | ~60 | Mandelbrot set |

**Recommended Batch Size:** All 9 in one sprint  
**Estimated Effort:** 1-2 days

---

## 🟠 TIER 2: SMALL SHADERS (2-3KB) - SECOND WAVE

**Count: 52 shaders | Total: ~135 KB**

Still relatively simple shaders with manageable complexity.

| Rank | Shader | Size (B) | Category |
|------|--------|----------|----------|
| 10 | `imageVideo` | 2,013 | Core |
| 11 | `gen_julia_set` | 2,099 | Generative |
| 12 | `gen_grok4_life` | 2,165 | Generative |
| 13 | `quantized-ripples` | 2,269 | Interactive |
| 14 | `gen_grok4_perlin` | 2,349 | Generative |
| 15 | `scanline-wave` | 2,385 | Retro |
| 16 | `luma-flow-field` | 2,399 | Image Processing |
| 17 | `mosaic-reveal` | 2,449 | Artistic |
| 18 | `gen_psychedelic_spiral` | 2,486 | Generative |
| 19 | `phantom-lag` | 2,486 | Glitch |
| 20 | `frosty-window` | 2,617 | Artistic |
| 21 | `gen_wave_equation` | 2,654 | Simulation |
| 22 | `parallax-shift` | 2,667 | Distortion |
| 23 | `rgb-glitch-trail` | 2,683 | Glitch |
| 24 | `ion-stream` | 2,703 | Generative |
| 25 | `gen-raptor-mini` | 2,746 | Generative |
| 26 | `radial-blur` | 2,779 | Blur |
| 27 | `pixel-sort-glitch` | 2,787 | Glitch |
| 28 | `chromatic-shockwave` | 2,789 | Chromatic |
| 29 | `chroma-shift-grid` | 2,793 | Chromatic |
| 30 | `selective-color` | 2,819 | Color |
| 31 | `echo-trace` | 2,827 | Interactive |
| 32 | `temporal-slit-paint` | 2,829 | Temporal |
| 33 | `time-slit-scan` | 2,833 | Temporal |
| 34 | `interactive-fisheye` | 2,836 | Interactive |
| 35 | `alucinate` | 2,848 | Core |
| 36 | `signal-noise` | 2,848 | Glitch |
| 37 | `chromatic-focus` | 2,850 | Chromatic |
| 38 | `rgb-ripple-distortion` | 2,854 | RGB |
| 39 | `static-reveal` | 2,863 | Reveal |
| 40 | `liquid-displacement` | 2,889 | Liquid |
| 41 | `spectrogram-displace` | 2,889 | Audio |
| 42 | `bubble-lens` | 2,901 | Distortion |
| 43 | `velocity-field-paint` | 2,904 | Interactive |
| 44 | `kimi_ripple_touch` | 2,920 | Interactive |
| 45 | `double-exposure-zoom` | 2,923 | Artistic |
| 46 | `sonic-distortion` | 2,926 | Distortion |
| 47 | `bitonic-sort` | 2,930 | Algorithm |
| 48 | `slinky-distort` | 2,942 | Distortion |
| 49 | `swirling-void` | 2,942 | Generative |
| 50 | `entropy-grid` | 2,945 | Generative |
| 51 | `liquid-jelly` | 2,958 | Liquid |
| 52 | `anamorphic-flare` | 2,959 | Lighting |
| 53 | `rgb-iso-lines` | 2,960 | RGB |
| 54 | `synthwave-grid-warp` | 2,967 | Retro |
| 55 | `digital-mold` | 2,979 | Artistic |
| 56 | `kimi_spotlight` | 2,980 | Interactive |
| 57 | `concentric-spin` | 2,981 | Geometric |
| 58 | `galaxy-compute` | 2,984 | Generative |
| 59 | `pixel-sorter` | 2,985 | Pixel Sort |
| 60 | `kaleidoscope` | 2,990 | Geometric |
| 61 | `pixel-repel` | 2,991 | Interactive |

**Recommended Batch Size:** 10-15 per sprint  
**Estimated Effort:** 3-4 sprints (2-3 weeks)

---

## 🟡 TIER 3: MEDIUM-SMALL SHADERS (3-4KB) - THIRD WAVE

**Count: 207 shaders | Total: ~740 KB**

The bulk of the shader library. These have moderate complexity.

### Selected High-Value Targets (first 30):

| Rank | Shader | Size (B) | Category |
|------|--------|----------|----------|
| 62 | `lighthouse-reveal` | 3,014 | Reveal |
| 63 | `temporal-echo` | 3,019 | Temporal |
| 64 | `sonar-reveal` | 3,045 | Reveal |
| 65 | `phase-shift` | 3,060 | Phase |
| 66 | `temporal-rgb-smear` | 3,063 | Temporal |
| 67 | `liquid` | 3,066 | Liquid |
| 68 | `interactive-fresnel` | 3,067 | Interactive |
| 69 | `liquid-rainbow` | 3,069 | Liquid |
| 70 | `vhs-tracking` | 3,077 | Retro |
| 71 | `elastic-chromatic` | 3,087 | Chromatic |
| 72 | `liquid-swirl` | 3,087 | Liquid |
| 73 | `julia-warp` | 3,098 | Warp |
| 74 | `waveform-glitch` | 3,115 | Glitch |
| 75 | `ambient-liquid` | 3,119 | Liquid |
| 76 | `signal-tuner` | 3,131 | Audio |
| 77 | `mirror-drag` | 3,135 | Interactive |
| 78 | `liquid-warp` | 3,137 | Liquid |
| 79 | `sonic-boom` | 3,138 | Distortion |
| 80 | `liquid-glitch` | 3,145 | Liquid |
| 81 | `rgb-delay-brush` | 3,153 | RGB |
| 82 | `hyper-chromatic-delay` | 3,158 | Chromatic |
| 83 | `data-slicer-interactive` | 3,161 | Interactive |
| 84 | `pixel-stretch-cross` | 3,161 | Pixel |
| 85 | `interactive-magnetic-ripple` | 3,164 | Interactive |
| 86 | `vortex-drag` | 3,169 | Vortex |
| 87 | `neon-pulse-edge` | 3,177 | Neon |
| 88 | `scanline-tear` | 3,178 | Glitch |
| 89 | `radial-rgb` | 3,181 | RGB |
| 90 | `gen_reaction_diffusion` | 3,184 | Simulation |

**Recommended Batch Size:** 20-30 per sprint  
**Estimated Effort:** 7-10 sprints (6-8 weeks)

---

## 🟢 TIER 4: MEDIUM SHADERS (4-5KB) - FOURTH WAVE

**Count: 171 shaders | Total: ~775 KB**

Moderate complexity - these shaders have significant functionality.

**Recommended Approach:** Pick strategically based on:
- Usage frequency (if metrics available)
- Visual impact
- Category diversity

---

## 🔵 TIER 5+: MEDIUM-LARGE AND BEYOND (5KB+) - BACKLOG

| Tier | Count | Strategy |
|------|-------|----------|
| Medium-Large (5-6KB) | 58 | Quarterly maintenance |
| Large (6-8KB) | 44 | Major version updates only |
| X-Large (8-12KB) | 37 | Requires dedicated sprints |
| XX-Large (12-16KB) | 12 | Major refactor required |
| Huge (>16KB) | 3 | Complete rewrite candidates |

### Huge Shaders (>16KB) - Complete Rewrite Candidates:

| Shader | Size (B) | Notes |
|--------|----------|-------|
| `quantum-foam` | 20,542 | Very complex - likely needs modularization |
| `aurora-rift-2` | 20,873 | Complex aurora effect |
| `aurora-rift` | 20,891 | Complex aurora effect |

---

## Upgrade Strategy Recommendations

### Phase 1: Pilot (Week 1)
- Upgrade all **9 Tiny shaders** to establish patterns
- Document common issues and solutions
- Create upgrade templates

### Phase 2: Small Scale (Weeks 2-3)
- Upgrade **52 Small shaders** in 3-4 batches
- Refine automation scripts based on patterns
- Build confidence with quick wins

### Phase 3: Volume (Weeks 4-8)
- Tackle **207 Medium-Small shaders**
- Consider automated refactoring for repetitive changes
- Prioritize by category/feature importance

### Phase 4: Selective (Ongoing)
- Target **Medium and larger** shaders based on:
  - User feedback
  - Bug reports
  - Feature requests
  - Performance issues

---

## Category Analysis of Small Shaders

### Tier 1-2 (<3KB) Shader Categories:

| Category | Count | Examples |
|----------|-------|----------|
| **Generative** | 14 | gen_orb, gen_grid, galaxy, gen_trails, gen_julia_set, gen_grok4_life |
| **Liquid** | 4 | liquid-displacement, liquid-jelly, liquid, liquid-rainbow |
| **Chromatic** | 6 | chromatic-shockwave, chroma-shift-grid, chromatic-focus, elastic-chromatic |
| **Glitch** | 6 | pixel-sort-glitch, signal-noise, rgb-glitch-trail, static-reveal, phantom-lag |
| **Interactive** | 7 | quantized-ripples, interactive-fisheye, kimi_ripple_touch, echo-trace |
| **Temporal** | 3 | temporal-slit-paint, time-slit-scan, temporal-echo |
| **RGB** | 4 | rgb-ripple-distortion, rgb-iso-lines, rgb-glitch-trail |
| **Distortion** | 4 | parallax-shift, sonic-distortion, slinky-distort, bubble-lens |
| **Retro** | 2 | scanline-wave, synthwave-grid-warp, vhs-tracking |
| **Artistic** | 4 | mosaic-reveal, frosty-window, digital-mold, double-exposure-zoom |

---

## Appendix: Complete Sorted List

<details>
<summary>Click to expand full list of 593 shaders</summary>

```
# Rank | Shader | Size (B)
-------|--------|----------
1 | texture | 719
2 | gen_orb | 1402
3 | gen_grokcf_interference | 1535
4 | gen_grid | 1594
5 | gen_grokcf_voronoi | 1630
6 | gen_grok41_plasma | 1648
7 | galaxy | 1682
8 | gen_trails | 1878
9 | gen_grok41_mandelbrot | 1883
10 | imageVideo | 2013
11 | gen_julia_set | 2099
12 | gen_grok4_life | 2165
13 | quantized-ripples | 2269
14 | gen_grok4_perlin | 2349
15 | scanline-wave | 2385
16 | luma-flow-field | 2399
17 | mosaic-reveal | 2449
18 | gen_psychedelic_spiral | 2486
19 | phantom-lag | 2486
20 | frosty-window | 2617
21 | gen_wave_equation | 2654
22 | parallax-shift | 2667
23 | rgb-glitch-trail | 2683
24 | ion-stream | 2703
25 | gen-raptor-mini | 2746
26 | radial-blur | 2779
27 | pixel-sort-glitch | 2787
28 | chromatic-shockwave | 2789
29 | chroma-shift-grid | 2793
30 | selective-color | 2819
31 | echo-trace | 2827
32 | temporal-slit-paint | 2829
33 | time-slit-scan | 2833
34 | interactive-fisheye | 2836
35 | alucinate | 2848
36 | signal-noise | 2848
37 | chromatic-focus | 2850
38 | rgb-ripple-distortion | 2854
39 | static-reveal | 2863
40 | liquid-displacement | 2889
41 | spectrogram-displace | 2889
42 | bubble-lens | 2901
43 | velocity-field-paint | 2904
44 | kimi_ripple_touch | 2920
45 | double-exposure-zoom | 2923
46 | sonic-distortion | 2926
47 | bitonic-sort | 2930
48 | slinky-distort | 2942
49 | swirling-void | 2942
50 | entropy-grid | 2945
51 | liquid-jelly | 2958
52 | anamorphic-flare | 2959
53 | rgb-iso-lines | 2960
54 | synthwave-grid-warp | 2967
55 | digital-mold | 2979
56 | kimi_spotlight | 2980
57 | concentric-spin | 2981
58 | galaxy-compute | 2984
59 | pixel-sorter | 2985
60 | kaleidoscope | 2990
61 | pixel-repel | 2991
62 | lighthouse-reveal | 3014
63 | temporal-echo | 3019
64 | sonar-reveal | 3045
65 | phase-shift | 3060
66 | temporal-rgb-smear | 3063
67 | liquid | 3066
68 | interactive-fresnel | 3067
69 | liquid-rainbow | 3069
70 | vhs-tracking | 3077
71 | elastic-chromatic | 3087
72 | liquid-swirl | 3087
73 | julia-warp | 3098
74 | waveform-glitch | 3115
75 | ambient-liquid | 3119
76 | signal-tuner | 3131
77 | mirror-drag | 3135
78 | liquid-warp | 3137
79 | sonic-boom | 3138
80 | liquid-glitch | 3145
81 | rgb-delay-brush | 3153
82 | hyper-chromatic-delay | 3158
83 | data-slicer-interactive | 3161
84 | pixel-stretch-cross | 3161
85 | interactive-magnetic-ripple | 3164
86 | vortex-drag | 3169
87 | neon-pulse-edge | 3177
88 | scanline-tear | 3178
89 | radial-rgb | 3181
90 | gen_reaction_diffusion | 3184
91 | magnetic-field | 3186
92 | luma-pixel-sort | 3190
93 | pixel-depth-sort | 3193
94 | gen_cyclic_automaton | 3202
95 | pixel-sand | 3206
96 | phosphor-decay | 3213
97 | crt-magnet | 3228
98 | scan-distort-gpt52 | 3234
99 | digital-lens | 3236
100 | chromatic-mosaic-projector | 3240
101 | chrono-slit-scan | 3240
102 | crt-tv | 3242
103 | liquid-fast | 3243
104 | liquid-mirror | 3249
105 | quad-mirror | 3254
106 | double-exposure | 3262
107 | light-leaks | 3263
108 | spiral-lens | 3264
109 | tile-twist | 3265
110 | luma-echo-warp | 3268
111 | pixelate-blast | 3268
112 | ascii-glyph | 3272
113 | lenia | 3273
114 | infinite-spiral-zoom | 3277
115 | page-curl-interactive | 3282
116 | tesseract-fold | 3284
117 | polar-warp-interactive | 3285
118 | echo-ripple | 3305
119 | refractive-bubbles | 3314
120 | quantum-ripples | 3329
121 | kaleido-scope-grokcf1 | 3334
122 | oscilloscope-overlay | 3338
123 | velvet-vortex | 3348
124 | spectral-brush | 3351
125 | magnetic-interference | 3353
126 | voxel-grid | 3355
127 | polka-dot-reveal | 3360
128 | scanline-sorting | 3361
129 | pixel-scattering | 3364
130 | liquid-oil | 3365
131 | divine-light-gpt52 | 3376
132 | directional-glitch | 3380
133 | stereoscopic-3d | 3384
134 | cyber-ripples | 3388
135 | thermal-touch | 3399
136 | data-scanner | 3403
137 | vertical-slice-wave | 3409
138 | xerox-degrade | 3423
139 | voronoi | 3427
140 | rgb-shift-brush | 3429
141 | cyber-lattice | 3432
142 | quantum-field-visualizer | 3436
143 | elastic-strip | 3449
144 | infinite-zoom-lens | 3450
145 | pixel-drag-smear | 3452
146 | chroma-depth-tunnel | 3453
147 | luma-melt-interactive | 3453
148 | physarum | 3458
149 | rgb-split-glitch | 3461
150 | virtual-lens | 3461
151 | reaction-diffusion | 3462
152 | spectral-waves | 3462
153 | digital-haze | 3467
154 | particle-swarm | 3468
155 | stipple-engraving | 3468
156 | kinetic-dispersion | 3472
157 | rgb-distance-split | 3476
158 | volumetric-god-rays | 3478
159 | pixel-stretch-interactive | 3479
160 | gen_capabilities | 3490
161 | pixel-sort-radial | 3501
162 | glitch-slice-mirror | 3502
163 | kimi_chromatic_warp | 3513
164 | fractal-image-surf | 3514
165 | luma-slice-interactive | 3514
166 | engraving-stipple | 3522
167 | datamosh | 3524
168 | holographic-projection-gpt52 | 3524
169 | melting-oil | 3531
170 | luma-magnetism | 3538
171 | heat-haze-gpt52 | 3541
172 | glitch-pixel-sort | 3548
173 | scan-distort | 3553
174 | sketch-reveal | 3570
175 | polka-wave | 3572
176 | wave-halftone | 3578
177 | dynamic-halftone | 3580
178 | hex-mosaic | 3580
179 | holographic-contour | 3582
180 | neon-edge-pulse | 3585
181 | liquid-prism | 3587
182 | spectral-slit-scan | 3587
183 | crt-clear-zone | 3591
184 | halftone | 3593
185 | interactive-glitch-brush | 3593
186 | vhs-tracking-mouse | 3595
187 | mouse-pixel-sort | 3599
188 | chroma-kinetic | 3606
189 | focal-pixelate | 3615
190 | pixel-focus | 3618
191 | thermal-vision | 3622
192 | neon-cursor-trace | 3623
193 | magnetic-edge | 3634
194 | interactive-rgb-split | 3638
195 | rgb-ripple-waves | 3644
196 | quantum-cursor | 3646
197 | laser-burn | 3648
198 | spectral-distortion | 3648
199 | sonar-pulse | 3656
200 | quantum-tunnel-interactive | 3659
201 | interactive-zoom-blur | 3667
202 | luminance-wind | 3668
203 | stipple-render | 3672
204 | cursor-aura | 3674
205 | spectral-rain | 3674
206 | magnetic-pixels | 3676
207 | scan-slice | 3679
208 | digital-glitch | 3683
209 | vortex | 3704
210 | chromatic-focus-interactive | 3708
211 | radial-slit-scan | 3708
212 | steampunk-gear-lens | 3714
213 | prism-displacement | 3721
214 | liquid-rgb | 3722
215 | heat-haze | 3725
216 | glass-brick-distortion | 3728
217 | bio-touch | 3731
218 | data-stream | 3744
219 | fractal-glass-distort | 3751
220 | neon-flashlight | 3751
221 | circular-pixelate | 3754
222 | cyber-halftone-scanner | 3756
223 | speed-lines-focus | 3758
224 | scanline-drift | 3766
225 | block-distort-interactive | 3778
226 | boids | 3797
227 | fiber-optic-weave | 3799
228 | neon-edges | 3803
229 | edge-glow-mouse | 3806
230 | slime-drip | 3806
231 | gen_fluffy_raincloud | 3812
232 | neon-light | 3812
233 | ripple-blocks | 3827
234 | neon-edge-diffusion | 3833
235 | interactive-pixel-wind | 3836
236 | ascii-lens | 3837
237 | rgb-topology | 3840
238 | moire-interference | 3843
239 | divine-light | 3846
240 | interactive-glitch | 3847
241 | chroma-vortex | 3851
242 | cymatic-sand | 3854
243 | neon-topology | 3860
244 | liquid-chrome-ripple | 3864
245 | temporal-distortion-field | 3864
246 | split-dimension | 3867
247 | data-moshing | 3869
248 | digital-moss | 3870
249 | spectral-smear | 3886
250 | holographic-sticker | 3894
251 | navier-stokes-dye | 3898
252 | glass-bead-curtain | 3901
253 | ascii-flow | 3902
254 | gen-cosmic-web-filament | 3908
255 | spirograph-reveal | 3912
256 | halftone-reveal | 3913
257 | kimi_nebula_depth | 3915
258 | kaleido-scope | 3943
259 | holographic-projection-failure | 3948
260 | neon-pulse | 3954
261 | hypnotic-spiral | 3958
262 | gamma-ray-burst | 3967
263 | interactive-emboss | 3974
264 | molten-glass | 3974
265 | complex-exponent-warp | 3976
266 | contour-flow | 3980
267 | vortex-distortion | 3980
268 | blueprint-reveal | 3992
269 | directional-blur-wipe | 4000
270 | pixel-explode | 4000
271 | adaptive-mosaic | 4001
272 | rgb-fluid | 4004
273 | prismatic-mosaic | 4006
274 | interactive-voronoi-lens | 4010
275 | neural-nexus | 4011
276 | fractal-noise-dissolve | 4013
277 | codebreaker-reveal | 4014
278 | impasto-swirl | 4017
279 | cross-stitch | 4018
280 | neon-strings | 4021
281 | motion-revealer | 4025
282 | glass-brick-wall | 4027
283 | fabric-zipper | 4030
284 | magnetic-ring | 4034
285 | vortex-warp | 4037
286 | crystal-refraction | 4039
287 | mirror-dimension | 4041
288 | strip-scan-glitch | 4045
289 | pixel-reveal | 4046
290 | pixel-sort-explorer | 4048
291 | gen-crystal-caverns | 4060
292 | elastic-surface | 4061
293 | liquid-warp-interactive | 4063
294 | reactive-glass-grid | 4064
295 | paper-cutout | 4072
296 | cyber-scan | 4077
297 | cyber-grid-pulse | 4082
298 | luma-force | 4085
299 | electric-contours | 4088
300 | gen_rainbow_smoke | 4088
301 | matrix-curtain | 4089
302 | refraction-tunnel | 4092
303 | ink-marbling | 4102
304 | interactive-origami | 4114
305 | kimi_liquid_glass | 4120
306 | hex-pulse | 4136
307 | magnetic-chroma | 4136
308 | infinite-fractal-feedback | 4145
309 | ring_slicer | 4150
310 | liquid-lens | 4154
311 | hex-lens | 4157
312 | liquid-smear | 4157
313 | glitch-cathedral | 4161
314 | physarum-gemini | 4164
315 | luma-topography | 4167
316 | quantum-prism | 4169
317 | physarum-grokcf1 | 4170
318 | cyber-rain | 4177
319 | night-vision-scope | 4182
320 | luminescent-glass-tiles | 4191
321 | luma-smear-interactive | 4194
322 | gravity-well | 4205
323 | neon-warp | 4216
324 | luma-velocity-melt | 4224
325 | origami-fold | 4231
326 | hyper-space-jump | 4236
327 | neon-fluid-warp | 4252
328 | chromatic-swirl | 4254
329 | rainbow-vector-field | 4268
330 | prismatic-feedback-loop | 4269
331 | warp_drive | 4274
332 | luma-refraction | 4278
333 | sliding-tile-glitch | 4279
334 | vhs-jog | 4288
335 | nano-repair | 4294
336 | chronos-brush | 4297
337 | reality-tear | 4304
338 | digital-compression | 4308
339 | rotoscope-ink | 4311
340 | cyber-glitch-hologram | 4316
341 | luma-glass | 4321
342 | charcoal-rub | 4327
343 | chroma-threads | 4327
344 | motion-heatmap | 4338
345 | mouse-gravity | 4338
346 | bubble-chamber | 4342
347 | data-slicer | 4344
348 | glitch-ripple-drag | 4347
349 | optical-illusion-spin | 4347
350 | interactive-kuwahara | 4352
351 | plastic-bricks | 4355
352 | knitted-fabric | 4359
353 | dimension-slicer | 4362
354 | gen_kimi_nebula | 4371
355 | glitch-reveal | 4373
356 | digital-reveal | 4374
357 | gen-lenia-2 | 4377
358 | video-echo-chamber | 4380
359 | neon-contour-interactive | 4383
360 | psychedelic-noise-flow | 4384
361 | fluid-grid | 4391
362 | black-hole | 4392
363 | ink-bleed | 4402
364 | lens-flare-brush | 4410
365 | ferrofluid | 4411
366 | holographic-projection | 4417
367 | radial-hex-lens | 4424
368 | holographic-prism | 4425
369 | neon-poly-grid | 4425
370 | spectral-glitch-sort | 4426
371 | vortex-prism | 4426
372 | cyber-focus | 4427
373 | tilt-shift | 4430
374 | chroma-lens | 4439
375 | signal-modulation | 4439
376 | crt-phosphor-decay | 4443
377 | vinyl-scratch | 4446
378 | infinite-video-feedback | 4450
379 | cyber-trace | 4457
380 | steamy-glass | 4459
381 | energy-shield | 4499
382 | nano-assembler | 4502
383 | voronoi-glass | 4504
384 | gen_hyper_warp | 4506
385 | aerogel-smoke | 4512
386 | fractal-kaleidoscope | 4529
387 | glass-wipes | 4530
388 | optical-feedback | 4541
389 | parallax-glow-compositor | 4544
390 | glass-wall | 4546
391 | magnetic-rgb | 4546
392 | interactive-ripple | 4552
393 | bubble-wrap | 4567
394 | neon-edge-reveal | 4567
395 | aero-chromatics | 4569
396 | iso-hills | 4569
397 | neon-contour-drag | 4573
398 | neon-pulse-stream | 4576
399 | flux-core | 4595
400 | crystal-facets | 4615
401 | voronoi-shatter | 4621
402 | kimi_quantum_field | 4624
403 | liquid-viscous-simple | 4625
404 | bayer-dither-interactive | 4630
405 | digital-decay | 4632
406 | honey-melt | 4640
407 | breathing-kaleidoscope | 4642
408 | ascii-shockwave | 4652
409 | liquid-time-warp | 4680
410 | frost-reveal | 4681
411 | gen_kimi_crystal | 4682
412 | frosted-glass-lens | 4701
413 | magnetic-luma-sort | 4721
414 | neon-echo | 4730
415 | sine-wave | 4731
416 | quantum-superposition | 4739
417 | pixel-rain | 4748
418 | pixel-storm | 4753
419 | voronoi-light | 4758
420 | phosphor-magnifier | 4766
421 | interactive-glitch-cubes | 4781
422 | predator-camouflage | 4797
423 | quantum-flux | 4799
424 | temporal-rift | 4810
425 | liquid-metal | 4816
426 | voxel-depth-sort | 4828
427 | kimi_fractal_dreams | 4834
428 | holographic-edge-ripple | 4848
429 | rain-lens-wipe | 4849
430 | color-blindness | 4853
431 | triangle-mosaic | 4864
432 | solarize-warp | 4878
433 | refraction-shards | 4881
434 | spectral-vortex | 4886
435 | interactive-voronoi-web | 4889
436 | x-ray-reveal | 4890
437 | vaporwave-horizon | 4915
438 | neon-ripple-split | 4966
439 | encaustic-wax | 4976
440 | spectral-mesh | 5002
441 | gemstone-fractures | 5023
442 | lichtenberg-fractal | 5040
443 | neon-edge-radar | 5063
444 | foil-impression | 5072
445 | cosmic-web | 5083
446 | cyber-organic | 5085
447 | hex-circuit | 5094
448 | sphere-projection | 5100
449 | kinetic_tiles | 5103
450 | crystal-illuminator | 5107
451 | cyber-slit-scan | 5112
452 | voronoi-zoom-turbulence | 5129
453 | prismatic-3d-compositor | 5138
454 | rorschach-inkblot | 5145
455 | crystal-freeze | 5147
456 | circuit-breaker | 5151
457 | cyber-lens | 5165
458 | cyber-magnifier | 5189
459 | generative-turing-veins | 5246
460 | gen-fractal-clockwork | 5259
461 | pixelation-drift | 5260
462 | kaleido-portal-interactive | 5268
463 | graphic_novel | 5270
464 | spectrum-bleed | 5271
465 | voronoi-faceted-glass | 5271
466 | data-stream-corruption | 5273
467 | gravity-lens | 5282
468 | cyber-rain-interactive | 5286
469 | voronoi-chaos | 5298
470 | magma-fissure | 5313
471 | paper-burn | 5317
472 | cyber-hex-armor | 5322
473 | venetian-blinds | 5353
474 | sequin-flip | 5369
475 | holographic-shatter | 5370
476 | stellar-plasma | 5390
477 | datamosh-brush | 5432
478 | hyperbolic-dreamweaver | 5442
479 | retro-gameboy | 5467
480 | rain-ripples | 5477
481 | interactive-halftone-spin | 5505
482 | ascii-decode | 5533
483 | liquid-touch | 5542
484 | bismuth-crystallizer | 5574
485 | generative-psy-swirls | 5601
486 | particle-disperse | 5628
487 | dynamic-lens-flares | 5638
488 | viscous-drag | 5640
489 | digital-waves | 5665
490 | gen-magnetic-ferrofluid | 5710
491 | interactive-film-burn | 5722
492 | interactive-pcb-traces | 5775
493 | volumetric-rainbow-clouds | 5809
494 | flip-matrix | 5861
495 | plasma | 5904
496 | kintsugi-repair | 5949
497 | cyber-physical-portal | 5989
498 | pin-art-3d | 6105
499 | biomimetic-scales | 6254
500 | rain | 6321
501 | cmyk-halftone-interactive | 6323
502 | cosmic-jellyfish | 6354
503 | holographic-glitch | 6357
504 | glass-shatter | 6375
505 | gen-quantum-mycelium | 6418
506 | gen-stellar-web-loom | 6474
507 | raindrop-ripples | 6525
508 | green-tracer | 6534
509 | pixel-wind-chimes | 6538
510 | crumpled-paper | 6582
511 | nebula-gyroid | 6612
512 | split-flap-display | 6633
513 | liquid-viscous-grokcf1 | 6675
514 | quantum-fractal | 6702
515 | volumetric-cloud-nebula | 6713
516 | poly-art | 6716
517 | radiating-displacement | 6748
518 | gen-silica-tsunami | 6847
519 | perspective-tilt | 6847
520 | radiating-haze | 7005
521 | time-lag-map | 7045
522 | liquid-viscous | 7057
523 | liquid-volumetric-zoom | 7094
524 | kimi_flock_symphony | 7094
525 | zipper-reveal | 7128
526 | gen-hyper-labyrinth | 7170
527 | lidar | 7191
528 | flow-sort | 7251
529 | log-polar-droste | 7408
530 | infinite-zoom | 7466
531 | liquid-zoom | 7466
532 | chromatic-folds-gemini | 7474
533 | snow | 7485
534 | gen-fractured-monolith | 7494
535 | cyber-terminal-ascii | 7504
536 | cosmic-flow | 7512
537 | nebulous-dream | 7618
538 | gen-micro-cosmos | 7651
539 | gen-prismatic-bismism-lattice | 7846
540 | liquid-perspective | 7937
541 | volumetric-depth-zoom | 7956
542 | gen-quantum-neural-lace | 8015
543 | byte-mosh | 8030
544 | voronoi-dynamics | 8073
545 | magnetic-dipole | 8162
546 | gen-neuro-cosmos | 8215
547 | astral-kaleidoscope-gemini | 8283
548 | anisotropic-kuwahara | 8286
549 | astral-kaleidoscope-grokcf1 | 8290
550 | rgb-glitch-displacement | 8342
551 | wave-equation | 8372
552 | multi-turing | 8408
553 | astral-kaleidoscope | 8435
554 | fabric-step | 8553
555 | gen-bismuth-crystal-citadel | 8700
556 | gen-holographic-data-core | 8715
557 | poincare-tile | 8894
558 | quantum-wormhole | 8913
559 | gen-cyber-terminal | 9105
560 | gen-brutalist-monument | 9182
561 | liquid-v1 | 9183
562 | iridescent-oil-slick | 9286
563 | chromatographic-separation | 9328
564 | dla-crystals | 9389
565 | gen-alien-flora | 9405
566 | gen-ethereal-anemone-bloom | 9413
567 | chromatic-manifold | 9528
568 | photonic-caustics | 10202
569 | astral-veins | 10295
570 | aurora-rift-gemini | 10311
571 | predator-prey | 10323
572 | bioluminescent | 10331
573 | neural-dreamscape | 10457
574 | chromatic-infection | 10488
575 | gen-isometric-city | 10940
576 | gen-bioluminescent-abyss | 11082
577 | ethereal-swirl | 11495
578 | gen-celestial-forge | 11739
579 | gen-biomechanical-hive | 12013
580 | _hash_library | 13002
581 | stella-orbit | 13297
582 | rainbow-cloud | 13430
583 | chromatic-folds-2 | 13489
584 | gen-art-deco-sky | 13728
585 | gen-chronos-labyrinth | 14080
586 | chromatic-folds | 14266
587 | chromatic-manifold-2 | 14645
588 | quantum-smear | 14752
589 | neural-resonance | 14898
590 | chromatic-crawler | 15389
591 | quantum-foam | 20542
592 | aurora-rift-2 | 20873
593 | aurora-rift | 20891
```

</details>

---

## Quick Reference: Priority Upgrade Queue

### Immediate Action (This Week):
```
texture, gen_orb, gen_grokcf_interference, gen_grid, 
gen_grokcf_voronoi, gen_grok41_plasma, galaxy, 
gen_trails, gen_grok41_mandelbrot
```

### Next Sprint (Next 2 Weeks):
```
imageVideo, gen_julia_set, gen_grok4_life, quantized-ripples,
gen_grok4_perlin, scanline-wave, luma-flow-field, mosaic-reveal,
gen_psychedelic_spiral, phantom-lag, frosty-window, gen_wave_equation,
parallax-shift, rgb-glitch-trail, ion-stream, gen-raptor-mini,
radial-blur, pixel-sort-glitch, chromatic-shockwave, chroma-shift-grid
```

---

*Document generated by automated shader size analysis*  
*Use this plan to prioritize upgrade efforts efficiently*

---

## External Project Shader Compatibility

The following external projects have weather/lighting shaders that should be kept compatible with this WGSL compute pipeline:

| Project | Shader(s) | Current Format | Compatibility Action |
|---------|-----------|----------------|----------------------|
| `webgpu_streetview` | `weather-post.wgsl` | WGSL render pipeline | Convert to compute pipeline with standard 13-binding header; map `WeatherParams` → `extraBuffer` |
| `weather_clock` | `shaders.js` (rain, splash, clouds, stars) | GLSL (Three.js) | Port to WGSL compute shaders using standard header; keep GLSL for WebGL fallback |
| `harborglow` | `lightShowNodes.ts` (god rays) | GLSL/TSL (Three.js) | Port to WGSL compute volumetric shaft shader using standard header; keep GLSL for WebGL fallback |

### Binding & Uniform Standard

All ported shaders MUST use the exact 13-binding header and the standard `Uniforms` struct defined in `upgrade_swarm.md` Appendix C. Project-specific parameters exceeding the 3 vec4 `zoom_params` capacity MUST be packed into `extraBuffer` (`@binding(10)`) as a structured float array. Do NOT extend the `Uniforms` struct.

### Re-use Existing Library Shaders

Before creating new weather shaders, extend existing equivalents already in this library: `rain.wgsl`, `snow.wgsl`, `atmos-fog-volumetric.wgsl`, `volumetric-god-rays.wgsl`, `night-vision-scope.wgsl`, etc.

### Porting Priority

1. **Phase A:** `webgpu_streetview` weather-post (already WGSL, just needs pipeline conversion)
2. **Phase B:** `weather_clock` rain/snow/splash (GLSL → WGSL port)
3. **Phase C:** `harborglow` god rays (GLSL → WGSL port)
