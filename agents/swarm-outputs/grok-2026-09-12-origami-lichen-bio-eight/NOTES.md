# Paper-fold / lichen / bioluminescent leftover eight — notes

Per shader: kept verbatim, packing, which ideas are in the diff.

## origami-fold
- Kept: Fold Speed / Shadow Strength / Fold Angle / Paper Opacity; mountain/valley from click parity; Kawasaki helper; paper fiber; crease specular; existing ACES formula.
- A packing: ACES display RGBA (C unused).
- Ideas in diff: Kawasaki buckle wrinkle along crease tangent; unfolded-side print-through mixed with paperOpacity.

## interactive-origami-coupled
- Kept: Fold Scale / Fold Depth / Viscosity / Vortex Strength; three crease normals; viscosity; mouse force + vortex; click density; A = vel/vorticity/dens.
- A packing: raw (vx, vy, vorticity, density). Prev mouse extraBuffer[133..134] stash (not a spring). Removed (0,0) A mouse overwrite.
- Ideas in diff: capillary pooling in crease valleys; Kármán street along crease 1.
- Floor: exact C loads; ACES display only; plasmaBuffer.

## gen-lichen-reaction-diffusion
- Kept: Pattern Density / Growth Rate / Zoom / Color Shift; evalLichen noise regimes (not rewritten as Gray-Scott); lichen_color ramp; mouse deposit; persistence.
- A packing: display RGB + pattern_density in A.a.
- Ideas in diff: thallus growth rings; apothecia cups.
- Floor: bounds guard; ripple xy treated as UV.

## gen-bioluminescent-reaction-diffusion
- Kept: Intensity / Speed / Scale / Mouse Influence; 8-tap Laplacian; luma feed/kill; mouse B seed; cyan/violet species.
- A packing: raw (A, B, luciferin-age, 1).
- Ideas in diff: luciferin quench from A.z age; excitation flash on advancing B.

## nano-repair
- Kept: Repair Radius / Decay / Glitch / Scanlines; health in A.r; block glitch; scanlines; red→green emission.
- A packing: raw (health, 0, 0, 1).
- Ideas in diff: healing front on |∇health|; weld flash where health rose vs C.
- Floor: exact C load; ACES; plasmaBuffer.

## digital-moss-rgba
- Kept: feed/kill/cross-inhibit/growSpeed; extraBuffer[133..138] spring; held plant / click clean; (A,B,C,D) packing.
- A packing: raw (A, B, C, D).
- Ideas in diff: B≈D territorial ridge; capsule stalks from high-B screen-up sample.
- Did not clone digital-moss shade taxis / rhizoids.

## bioluminescent
- Kept: Spread / Density / Glow / Spore Count; growth in A.r; click spores; four palettes; veins; SSS.
- A packing: raw (growth, 0, 0, 1).
- Ideas in diff: spore tropism toward live click inoculum; quorum flash vs neighbor average.
- Floor: zoom_config no longer stolen as GrowthRate/ColorMode (engine mouse/time); plasmaBuffer; exact C; ACES; bounds guard.

## bioluminescent-blackbody
- Kept: Spread / Density / Glow / Spores; blackbodyColor Kelvin map; click spores; growth field.
- A packing: raw (growth, heat, 0, 1).
- Ideas in diff: leading-edge heat on advancing front; cooling lag in A.g.
- Stripped leftover clock-ring / IQ spectral overlay from HEAD. Floor: exact C; honest bass pulse.
