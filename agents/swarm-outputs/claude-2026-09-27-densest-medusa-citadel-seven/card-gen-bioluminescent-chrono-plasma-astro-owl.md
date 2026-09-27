```
SHADER: gen-bioluminescent-chrono-plasma-astro-owl
IDENTITY: a raymarched owl (ellipsoid body/head, mirrored flapping box wings with fbm feathers, sphere eyes) orbited by
  the mouse, in front of an fbm nebula with a kaleidoscopic lattice.
KEEP VERBATIM: owl SDF parts and wing flap (L124-194), gravity twist (L132-137), kaleido fold (L115-120), nebula +
  lattice (L227-255), mouse orbit camera (L281-286), ripple field (L99-112), FFT reads, 4 slider roles (x wing plasma
  distortion, y core gravity, z nebula density, w temporal echo), saved params.
ADD (native ideas):
  1. Gravity-lensed nebula — missed rays are bent by the same g/(r+0.1) twist around the owl's core (use the ray's
     closest approach to the core, tracked in the march) before getNebula (L329-331), so the lattice and nebula swirl
     around the owl; strength follows slider y (core gravity) — couples the SDF warp to the background.
  2. Lattice plumage — project the kaleido hex lattice (L248-252) onto the body/wings in object space as thin emissive
     cell edges on the feathers (L305-310), so owl and background share one lattice; mids may add folds.
  3. Nebula-dissolve fog — the distance fog at L325 samples the nebula along rd (cheap: reuse the miss nebula function
     at the ray direction) instead of a hard-coded colour, so distant feathers melt into the actual background.
FIX/WIRE:
  - Double tone map: C holds Reinhard+gamma output, mixed back and re-toned each frame -> grey floor ~0.13 that never
    decays (0.43 at echo 1). A = HDR linear, C decoded as HDR, ACES on writeTexture only. Keep echo persistence role.
  - L222 miss-as-hit: 100 steps exhausted with t<20 leaves mat_id 0 -> black; treat exhaustion as a miss.
  - L307 mix factor p.y*0.5+0.5 extrapolates -> negative red -> pow(neg, 1/2.2) NaN; clamp.
  - L140 body scaled by 1/(1+bass*0.12) without rescaling the distance -> overstep; multiply back.
  - Miss depth passes readDepthTexture through (L293) -> write 0 on miss; hit 1 - t/20 is fine.
  - Canonical header with Features/Upgraded/Ideas/A packing; JSON gains a true features array.
  - Optional: shrink the step if twist/fbm makes holes at high sliders.
FORBID: barbule thin-film, ocellus eye-spots, primary-feather slots, beak glint, flap ghost, feather-current lanes,
  cyber-iris, tapetum eyeshine, Purkinje catchlight, dilator stroma, spring cursor.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha; C read back as HDR echo.
DEFAULT-LOOK SHIFT: grey haze floor gone (blacks return); background swirls round the owl; feathers show lattice.
```



## Refinement (implementing agent, 2026-09-27)

IDEAS AS SHIPPED (all visible at audio = 0; tagged `// Idea N:` in WGSL):
  1. Frame-dragged sky — L288-296 (`dragSky`), used at L336-338. Each view ray is twisted about world Y by the
     SAME `coreTwistAngle` (L137-139, now shared with map()) using the ray's analytic closest approach to the core.
     Renamed from "gravity-lensed": the catalog already has inverse-square lensing / lensed starfields, and this is
     a pure Y-twist (no radial deflection / Einstein ring). Numpy: drag 0.17 rad at screen edge -> ~0.56 rad at the
     silhouette at default y=0.5; ~31% of sky lattice pixels change. y = 0 and no ripple -> HEAD sky.
  2. Lattice plumage — L371-380. The sky lattice was factored into `chronoLattice` (L127-134, getNebula uses it
     unchanged) and evaluated on the direction from the core in the owl's twisted/breathing frame, emissive
     cyan edges (~19% of owl pixels at default). Brighter on the shadow side; fft_wing band adds.
  3. Nebula-dissolve fog — L388-394. Fog colour is the actual frame-dragged sky (was flat (0.05,0,0.1)), plus a
     rim^4 silhouette fringe; factor capped at 0.85. Fog 0.21-0.36 on the body at default.

FIXES (verified against HEAD):
  - Double tone map: CONFIRMED (fixed point ~0.127 grey at echo 0.2). A/C now HDR linear; ACES(col*0.8)+gamma on
    writeTexture only (L402-420).
  - Step exhaustion shaded as mat 0: CONFIRMED. Exhaustion is a miss unless last d < 0.02 (L227-258). Step 0.8,
    128 iterations; numpy vs a 0.25-step reference: 0 holes at default, <=9/5184 at x=0.1,y=2.
  - p.y mix extrapolation: CONFIRMED but rare (needs p.y < -1.29); clamped (L366).
  - Bass breathe: card claim "overstep" is WRONG — dividing q by (1+0.12 bass) makes d an UNDERestimate (safe).
    Still multiplied back (L214) so the march is exact; no-op at bass 0.
  - Miss depth passthrough: CONFIRMED; miss depth now 0, hit 1 - t/20.
  - EXTRA (not in card): rd used uv.y top-down, so the owl rendered UPSIDE DOWN (head at the bottom). Flipped
    (L332-334); numpy: head rows now at the top. Mouse orbit formula unchanged.
  - Alpha: owl now solid (1 - fog), sky keeps luma alpha (HEAD comment claimed this but never did it).

KEPT VERBATIM: owl SDF parts/flap/fold, twist math (now a shared helper), kaleido, nebula loop, lattice formula,
  camera, ripples, FFT reads, 4 slider roles, saved params (byte-exact). JSON: added true `features` only.
REFUSED: radial lensing / Einstein ring (catalog-saturated).
A PACKING: HDR linear RGB (pre-ACES echo history) + semantic alpha; C read back as HDR.
DEFAULT-LOOK SHIFT (GPU QA): owl now upright; grey haze gone (true blacks); sky shears into a vortex round the owl;
  cyan lattice cells on the plumage; owl edges melt into the nebula; ACES highlights slightly brighter than Reinhard.

STATUS: final
