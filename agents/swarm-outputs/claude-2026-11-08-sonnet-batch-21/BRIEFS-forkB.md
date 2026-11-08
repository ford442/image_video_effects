# sonnet/batch-21 — fork B briefs (written BEFORE any WGSL edit)

Shaders: gen-hyper-labyrinth, gen-chromodynamic-glass-labyrinth, gen-fractured-monolith (all 2nd passes; existing `Ideas:` lines are kept and not repeated).
Baselines: `baseline/<id>_before.png` plus HEAD time strips `forkB/head_strip_<id>.png` (T0 = 0.5/3/6/9/12/17).

## HEAD defects found while reading + rendering (rescues, NOT ideas)

| shader | defect at HEAD | evidence |
|---|---|---|
| gen-hyper-labyrinth | **camera inside a wall**: gyroid walls fill space, orbit camera (r=8) sits in `|val|<th/2` for a large share of time; ray hits at t≈0 → flat colour / dark metal | strip: T0.5 pale-blue flat, T3 purple flat, T9 black; only T12/T17 show the maze. Also uv.y is pixel-space (down) and `right = cross(up, fwd)` is mirrored → upside-down/mirrored view (the file's own comment "mouse up = look up" assumes right-side-up) |
| gen-chromodynamic-glass-labyrinth | **camera on the lattice axis (x=y=0)** passes through cell boundaries at every integer t (z odd); rotating cube corners (reach radius 1.21) contain the point at radius 1 → camera in glass | numpy probe: map(0,0,z) = −0.006 @t=3, −0.026 @t=12, −0.026 @t=17; strip T3/T12/T17 flat gradient |
| gen-fractured-monolith | (a) **upside-down camera**: uv.y down + vv=+y → floor (cyan seam-pool grid) renders at the TOP, sky gradient at the bottom; (b) **shard rotation unbounded and about the slab axis**: `localRot ∝ time` → slab erodes to a few fragments by t≈10–17; (c) `time*audioReactivity` as phase argument (bob, yaw, floor wave) → phase jumps by `time*Δaudio` whenever audio changes (t=300 s: several rad/frame) | strip: slab intact @0.5, mostly gone @12/17; plate with grid at top |

## Idea Cards

```
SHADER: gen-hyper-labyrinth
IDENTITY: neon gyroid 4D maze orbited from outside; walls glow with cyan/magenta vein pattern, ember/arc key light, afterglow trails.
KEEP VERBATIM: 4 params + roles (scale→gyroid freq, morph→4D rotation rate, neon glow, wall thickness); 4D XW rotation + YZ drift; gyroid sum val; 3-point lighting; veins (pattern, pulse, click fronts, held swirl); Ideas 1–4 (midline, W hue, cul-de-sac, treads); A = persisted raw neon RGB + alpha; ACES on display only.
MECHANISM (T1) |val|−th/2 is a uniform-thickness shell; deeper = thickness that varies with the 4th coordinate the shader already rotates. (T2) a real corridor is darker in its crevices (inter-reflection loss). (T3) q.w and n are already computed, map() is available for taps. (T6) C is raw neon history; no new continuity needed → no history idea.
ADD:
  5. W-modulated wall thickness (tactic 4: "Wall Thickness" made spatially varying along the 4D slice): th·(1+0.3·sin(0.5·q.w)); mean thickness unchanged, walls swell/thin as the 4D rotation sweeps — a 4D maze, not a static 3D gyroid.
  6. Corridor step-count AO (§12.2E "Step-count AO"): 5 taps along n, multiplies the dark metal base + rim only (not the HDR neon, which is emissive) → crevices read as corridors.
RESCUE: camera noclip — if the ray starts inside a wall, march out through it (|d| steps) before the primary march so every frame shows the maze; camera basis fixed (right-side-up, un-mirrored) — pointer swirl uses the same basis.
FORBID: new spring / extraBuffer state, IQ palette, change to veins/glowCol, new params.
A PACKING: unchanged — A = persisted raw neon RGB + alpha.
FORMULA ADMISSION: AO row is in the raymarched-SDF table; consumes map()+n; deleting it leaves the same maze. Thickness idea consumes q.w; deleting it leaves the original maze.
```

```
SHADER: gen-chromodynamic-glass-labyrinth
IDENTITY: flight through a lattice of rotating liquid-glass cubes-with-spherical-hollows, refracted per wavelength with Beer-Lambert interior march.
KEEP VERBATIM: lattice fold (cell_size=4/density), checkerboard spin, box∖sphere smax, 4 params + roles (density, ior, dispersion, chromatic phase=palette offset), interior() per-wavelength march + Beer-Lambert, per-cell ior hash, bass/treble/mids as wavelength spread/ior nudge, palette tint, alpha = transmission coverage, ACES on display RGBA.
MECHANISM (T1) eta spread is linear ±disp; real glass is Cauchy n(λ)=A+B/λ². (T2) F is a fake (1−cosθ)³ with F0=0; real F0=((n−1)/(n+1))² follows the ior slider; the exit face also loses energy to reflection. (T3) `refl` is computed and only used for a white spec dot — promote it to a short march into the lattice (the "hyper-reflective" of the description). (T6) no history is read; none added.
ADD:
  4. Cauchy dispersion (§12.2F): R/G/B eta offsets ∝ (1/λ²−1/λg²) at 650/550/450 nm instead of symmetric ±, dispersion slider = B scale (same role), bass/treble spreads kept.
  5. Fresnel–Schlick with F0 from the per-cell ior (§12.2F), replaces (1−cosθ)³; exit-face transmittance (1−F_exit) multiplies the interior transmission so denser glass is darker + more mirror-like.
  6. Reflection march: ≤14 steps along `refl` through map(); the neighbouring cell's glass tint (palette at the hit) replaces the lone white spec in the Fresnel branch; spec kept on top.
RESCUE: camera-in-glass — start ray marched out of the solid through the glass (Beer-Lambert-tinted by the path) when map(ro)<0, so the on-axis ride never shows a flat in-glass frame.
FORBID: springs, ripples, new params, change to palette/param ranges (structuralDensity 2.0 etc. byte-exact), any change to cell fold/spin.
A PACKING: unchanged — ACES display RGBA, alpha = transmission coverage.
FORMULA ADMISSION: Cauchy + Schlick are in the optical table and this IS a dispersive glass shader; both consume ior/eta/n already computed; deletion test passes both ways. Reflection march consumes map()/refl already computed.
```

```
SHADER: gen-fractured-monolith
IDENTITY: tall cell-fractured slab levitating over a dark wavy liquid, seams glowing, light pooling on the water.
KEEP VERBATIM: 4 params + roles (spread, levitation speed, glow, rotation speed); box ∩ cell-shard SDF with drift/ crackNoise; chips; seam glow, pulse, dust; Ideas 1–4 (shard tint, glints, seam pool, rising pulse); display-RGBA history with 0.82 decay; ACES.
MECHANISM (T1) floor = one sin·cos; a levitating mass pushes liquid → dispersive ring train. (T2) real levitating debris does not move in lockstep; its edges are chipped bright where the surface bends sharply. (T3) cellId + hash31(cellId) is already computed per shard → per-shard phase; shardDist is available for curvature taps. (T6) C is display colour with decay; unchanged.
ADD:
  5. Per-shard levitation phase (tactic 3/4): each shard adds its own slow vertical bob (phase from hash31(cellId), rate from Levitation Speed, amplitude scaled by Fracture Spread) so seams breathe instead of the slab moving as one block; zero at spread=0.
  6. Downdraft ring train on the liquid (§12.2D deep-water dispersion): 3 wavelengths, phase speed ∝ √λ, radiating from under the slab, amplitude ∝ |slab velocity| from the same bob; added to `wave` in map(), so normals + reflections follow.
  7. Chipped-edge wear (§12.2E SDF curvature): 6 taps at e=0.04 on monolith hits → convex edges lift toward a pale rim tint, concave seams darken; shading only.
RESCUES: flip camera y (right-side-up); shard rotation bounded: each shard rotates about ITS OWN centre by a bounded sin wobble (0 at t=0 and at rotation-speed 0) — slab no longer erodes with time; audio no longer multiplies absolute time in phase arguments (bob/yaw/floor wave share helper fns with the seam-pool code) — amplitudes still react.
FORBID: springs, ripples, IQ palette, new params, replacing the slab/liquid, changing seam pool/pulse/dust.
A PACKING: unchanged — ACES display RGBA history.
FORMULA ADMISSION: dispersion row = liquid table, floor IS liquid; curvature row = hard-surface SDF table; shard phase consumes cellId/hash. Deletion test OK for each.
```

Cross-batch formula use (for the coordinator's §12.4 tally): Step-count AO ×1 (hyper-labyrinth), SDF curvature ×1 (monolith), Cauchy ×1, Fresnel–Schlick ×1 (glass), deep-water dispersion ×1 (monolith).
