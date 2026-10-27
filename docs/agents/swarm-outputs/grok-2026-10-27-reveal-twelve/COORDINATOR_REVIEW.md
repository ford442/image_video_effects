# Coordinator review — reveal-twelve (2026-10-27)

Cards were written before the WGSL. Each numbered idea is named in the shader. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Ideas in the diff | Formula | Packing |
|---|---|---|---|---|
| sonar-reveal | pass | range rings; beam spread | none | ACES display RGBA |
| codebreaker-reveal | pass | head and tail; decrypt mask in A.a | none | display RGB + mask in A.a |
| sonar-pulse | pass | deep-water phase speed; cylindrical falloff | §12.2D dispersion | ACES display RGBA |
| blueprint-reveal | pass | major grid; registration mark | none | raw mask in A.r |
| pixel-reveal | pass | scanline sort; tile mortar | none | display RGB + memory in A.a |
| sketch-reveal | pass | contour pen; wash granulation | §12.2C granulation | raw `(edge, wash, sketchBase, alpha)` |
| night-vision-scope | pass | phosphor lag; fixed-pattern streaks | none | ACES display RGBA |
| motion-revealer | pass | coherence gate; motion hold | §12.2A coherence | `(live RGB, motion)` |
| thermal-touch | pass | 9-point conduction; inverse-square + isotherms | §12.2D laplacian; §12.2F inverse-square | raw heat in A.r |
| digital-reveal | pass | finite drops; glyph wipe | none | mask in A.r |
| x-ray-reveal | pass | anode heel; anti-scatter grid | none | ACES display RGBA |
| neon-flashlight | pass | inverse-square core; hot core | §12.2F inverse-square | ACES display RGBA |

Formula use: dispersion once, granulation once, structure-tensor coherence once, 9-point laplacian once, inverse-square twice (thermal-touch, neon-flashlight). No row on three files.

Dead springs and dead `plasmaBuffer[1..]` reads are fixes, listed in NOTES, not counted as ideas.

Checklist: cards exist; ideas are commented in the main path; kernels and param roles kept; no shared spring or IQ stamp; A packing matches the C read; Naga 12/12; extraBuffer clean; dead sliders 0 new.
