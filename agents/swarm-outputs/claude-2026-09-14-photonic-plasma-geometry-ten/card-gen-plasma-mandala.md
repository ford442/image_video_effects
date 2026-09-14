SHADER: gen-plasma-mandala
IDENTITY: Radially folded plasma mandala — dihedral angular fold (symmetry sectors with mirror), trig-sum plasma + FBM detail, cosine hue cycling, glow ring at r=0.5, fold-seam highlight, mouse-held pulls center.
KEEP VERBATIM: plasma(), fbm2()/noise2()/hash21(), sector fold math, hue cycling, seam highlight, vignette, spark, slider mappings (symmetry mix(3,12), spin mix(0.1,1), zoom mix(0.5,3), glow mix(0.5,3)), ACES on col*glow_scale*1.05.
ADD (2 native ideas):
  1. Diocotron-instability ring — the glow ring radius is perturbed by an azimuthal mode locked to the petal group (one wavelength per mirrored sector) plus a first-harmonic roll-up; rotates with spin (E x B drift), amplitude grows with bass; thin vortex-core highlight on the crests.
  2. Dihedral click pulses — each u.ripples[i] origin is folded into the same D_n fundamental domain as the pixel, so one click's expanding wavefront echoes in every petal (loop min(u32(config.y),50), age<2.5, never uses ripple.w). Adds to color and alpha.
FLOOR FIXES: plasmaBuffer[0].xyz now clamped 0..1; removed duplicate unused aces() helper; added click-ripple response (had none); Uniforms comment lists slider names; header refreshed (2026-09-14). Already OK: 13 bindings, ACES + semantic alpha (luma/ring/seam/pulse), same RGBA to writeTexture + dataTextureA, depth written, no dataTextureB/C writes, no extraBuffer use, no fake audio, all 4 sliders live, JSON params/features present (ids untouched).
FORBID: fake audio (config.y/zw/zoom_config.x), extraBuffer outside 133..138, dataTextureB writes, replacing the fold/plasma motif, renaming param ids.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok (AUDIT PASS) / sliders x,y,z,w live
