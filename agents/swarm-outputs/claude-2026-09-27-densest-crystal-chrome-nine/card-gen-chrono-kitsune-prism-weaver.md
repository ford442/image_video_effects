```
SHADER: gen-chrono-kitsune-prism-weaver
IDENTITY: a fox-spirit seen from the front — a sine-wobbled sphere body at z=5 with 3-9 tapered tails fanning radially
  and streaming away with a travelling weave, a volumetric glow shell and a radial HDR echo feedback.
KEEP VERBATIM: mapKitsune body + tail loop (L85-111), tetrahedral calcNormal, bounding-sphere early-out (L178-182,
  Batch 37 optimizer), glow accumulation (L191-206), echo feedback structure (L237-251, textureLoad C), ACES on display
  only, 4 slider roles (x prism_hue_shift, y tail_count, z weave_tightness, w chrono_echo), saved params/updatedParams,
  FFT reads extraBuffer[5..12] (legit read-only).
FIX/WIRE:
  - Depth inverted (L254-255: t/FAR_CLIP on hit, 1.0 on miss) -> near 1, miss 0.
  - uv not flipped (L162) while mouse is flipped "bottom-up" (L147) and the light (1,1,-1) ends up lighting from
    screen-bottom -> flip uv so screen top = +y; mouse and light consistent.
  - Step exhaustion shaded as hit (L210 hit_surface = in_bounds && t < FAR_CLIP) -> require d < SURF_EPS (or a
    loose threshold) for a hit.
ADD (native ideas):
  1. Body prism, tails as spectral bands — mapKitsune only returns material 1/2 (L110). Return the nearest tail index
     too; the body is the prism: light entering the body leaves split into discrete spectral bands, one band per tail
     around the fan (red..violet), with Prism Hue Shift rotating the band order. The body stays white-hot/clear.
  2. Heartbeat transfer — couple the body's sine wobble (L88-91) to the tail weave: a pulse born in the body travels
     out each tail with a delay proportional to distance along the tail (tp.z), swelling tail radius and glow as it
     passes, so the body's heartbeat visibly runs down the nine tails.
  3. (optional) Tail unfurl — y maps via floor(p*9) clamped 3..9 (L159), so 0.1..0.333 is dead and each step pops.
     Use a fractional count: the newest tail grows in length/opacity continuously. At default 0.8 the tail count must
     stay 7 fully grown (check numerically).
FORBID: kitsunebi/fox-fire wisps at tail tips, nine-tail thin-film, Cauchy glass armour, spring cursor, ripple rings,
  IQ palette stamp, the (missing) chrono-void lattice as a new system.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD) — keep.
DEFAULT-LOOK SHIFT: image now upright; tails spectrally banded. Not GPU-verified.
```

STATUS: draft (coordinator) -> superseded by Final below

## Final (implementer, 2026-09-27)

Audit claims verified against HEAD — all TRUE (depth inverted L254-255; uv not flipped L162; stalled rays shaded as hits L210;
tail count popped via floor, 0.1..0.333 clamped to 3). Audit MISSED a bigger one: at HEAD the tails were INVISIBLE —
numpy port (scratchpad head_port.py, 96x54, default sliders) gives 0 tail hits, 5.8% body hits: tails run parallel to +z in a
0.8 ring directly behind a radius-1.2 body at z=5, so the body occludes the whole fan (camera never moves, mouse only rotates rd).

FIX (floor): TAIL_SPLAY 0.55 (tails shear outward with length; SDF scaled by 1/sqrt(1+0.55^2)); bounding sphere recentred
(0,0,16.5) R 17 to cover the fan (HEAD sphere already spanned the whole 16:9 frame, so no early-out loss); uv.y flipped;
hit requires d < HIT_EPS 0.04; depth near 1 / miss 0 (+ glow relief). A was already HDR pre-ACES and C read as HDR: no double
tone-map here. Numpy (new_port.py): default -> 7 tails visible, 6.6% tail + 5.8% body px, stall-misses 1.9%; Lipschitz p99 at
defaults 1.38 (HEAD 1.12), max 2.8 only at weave=7 (HEAD 1.95). Found+fixed my own bug in port: fract()-based pulse was
discontinuous at the wrap (Lip 3.7) -> peaks now measured to nearest repeat.

Ideas as implemented:
  1. Body-as-prism tail spectrum — spectralBand L109-121 (bump fit 680..400 nm, not a cosine palette); mapKitsune returns nearest
     tail band L163-169; band_shift L231 (Prism Hue Shift 0..5 = one full rotation of band order; HEAD integer values were no-ops);
     spectral halo L279 + L323; body white core + rim dispersed into the band of the tail rooted behind that rim angle L304-311;
     tails one discrete band each L313-317.
  2. Heartbeat transfer — heartbeat() L99-107 (lub-dub, continuous periodic); body swell L131-133; pulse travels out each tail at
     PULSE_SPEED with delay s/9 s, swelling girth (L158-162) and emission (L279, L316). Constants L66-71. Visible at audio 0
     (numpy: tail px vary ~15% through a beat).
  3. Tail unfurl — fractional count L223-229, newest tail grows length+girth and fan spacing eases open L136-154. Default 0.8 -> 7.2
     -> grow = smoothstep(0.35,1,0.2) = 0 -> exactly 7 tails (verified). 0.1..0.333 still clamps to 3 (HEAD MIN_TAILS design).
Audio (not ideas): bass -> heartbeat amplitude (+80%), tail glow + click burst (HEAD); mids -> small band shift + HEAD hue;
  treble/FFT bins -> halo shimmer (HEAD).
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD); C read exactly, radial echo unchanged.
JSON: params/updatedParams byte-exact; features + upgraded-rgba, mouse-driven (pre-existing true tags kept). Description's
  "chrono-void lattice" is untrue at HEAD — left as is (not empty; lattice forbidden as a new system).
Refused/skipped: no ripples/spring added (HEAD has none); lattice not added.
DEFAULT-LOOK SHIFT: image upright; a fan of 7 spectral tails now visible around the body (was a lone wobbly sphere), halo
  spectral, body whiter with a dispersed rim, rhythmic lub-dub swell. Not GPU-verified.

STATUS: final
