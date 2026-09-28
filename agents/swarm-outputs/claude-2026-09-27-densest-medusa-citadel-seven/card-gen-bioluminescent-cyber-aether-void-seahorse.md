```
SHADER: gen-bioluminescent-cyber-aether-void-seahorse
IDENTITY: a raymarched side-on seahorse (body, belly, head, snout, coronet, fin, folded fractal tail) with fbm glowing
  bands against a domain-warped nebula.
KEEP VERBATIM: body/head/snout/coronet SDF, fractal tail fold loop (L148-159), fbm + bioPalette (L56-101), nebula
  (L280-291), mouse-hold glow, 4 slider roles (x palette shift, y audio gain, z void intensity, w evolution speed),
  saved params.
ADD (native ideas):
  1. Sagittal fin-ray membrane — the dorsal fin currently sits in plane x=-0.56 (edge-on, 0.032 wide, buried in the
     body: never seen). Move it into the z≈0 sagittal plane on the back, ridged by fin rays whose undulation is the
     existing finWave (L138), and lit as a translucent membrane by the fill light (L253) — the seahorse's real
     propulsor becomes visible.
  2. Fold-plane filament threads — build the tail's orbit trap from the per-fold min(|pTail.x|, |pTail.y|) inside the
     fold loop (L150-154), so thin cyan threads trace every curl of the fractal tail (replaces the trap that is >=0.55
     everywhere at L271); a phase per fold index lets the threads light up fold by fold (bass pulses).
FIX/WIRE:
  - No tone map (raw HDR out) -> ACES on writeTexture only; A = HDR; C decode consistent (feedback is linear 0.12 now).
  - Mouse X only rolls the image: rotate(mx) applied to rd.xy and ro.xy with ro.xy = 0 (L206, L209) -> real yaw orbit
    of ro around the seahorse; default mouse must reproduce HEAD's default side profile.
  - Gated smin (L142, L156) runs only when the part is already nearest -> field jumps up to k/4 -> seams; blend
    unconditionally.
  - L289 "near-miss halo" is just the nebula — make it true (track min distance along missed rays, exp glow). This is a
    FIX of a false claim, not an idea (silhouette halo is catalog-saturated).
  - t = time * evolution_speed (L198) jumps when the slider moves — acceptable to keep (no state to integrate); leave,
    but never multiply time by audio.
  - Miss depth writes neb*0.12 -> 0 on miss.
  - Header Ideas + A packing; drop the generic 2D ripple rings only if you replace them with nothing (keep click
    ripples — they are HEAD behaviour).
FORBID: tail-fin Karman wake, silhouette halo as an idea, thin-film, spring cursor, Stokes-shift afterglow.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha.
DEFAULT-LOOK SHIFT: fin now visible on the back; tail glow becomes threads instead of a uniform wash; tone-mapped.
```

STATUS: draft (coordinator)

## Refinement (implementing agent, 2026-09-27)

Audit claims checked against HEAD (numpy port of map() in scratchpad `seahorse/head.py`, `new.py`):
- Fin edge-on at x=-0.56: TRUE, but "never seen" is FALSE — it shows as a 1-2 column sliver down the back-left. Still replaced.
- Tail trap wash: TRUE — trap included the last fold whose length is the bead radius, so trap <= 0.1 on every tail pixel -> glow >= 0.55 (uniform). HEAD also fed min(trap, dFin)=0 into the fin, so the whole fin was full cyan wash.
- Gated smin seams (L142, L156): TRUE (jump k/4 = 0.025 fin, 0.125 tail).
- Mouse X roll (L206/209): TRUE. Miss depth neb*0.12: TRUE. No ACES: TRUE. False "near-miss halo": TRUE.
- Extra finding: rd.y = +(uv.y-0.5) with uv.y=0 at screen-top, so the seahorse rendered HEAD-DOWN (tail off the top). Flipped to (0.5-uv.y); flagged as a default-look shift.

Idea 2 swapped from "fold-plane filament threads": the "tail" is a dust of r=0.1 beads (4 folds, offsets 0.2), so fold-plane seams
rarely touch any surface and "orbit-trap filament glow" is already catalog-saturated. Replaced by a fold-address cascade native
to the same fold loop.

FINAL IDEAS (WGSL):
  1. Sagittal fin-ray membrane — `finRayField` L118-127, SDF in map() L163-179, shading L320-333. Membrane in z≈0 plane off the
     lower back, 15 parallel rays, scalloped rim, HEAD finWave now bends it out of plane (pinned at back); translucent two-sided
     webbing + ray pulses phase-locked to the wave.
  2. Fold-tree chromatophore cascade — fold address in the tail loop L183-196, flash L343-350. Beads flash in fold-address order
     (first fold = MSB), so light hops between mirror siblings through the fractal tail. Period 4 s at evolution 1. Visible at audio 0.
FIXES: ACES on writeTexture only, A/C = HDR (consistent 0.12 blend); yaw orbit (default mouse 0.5 = HEAD framing); unconditional
  smin for fin (k 0.08) and tail (k 0.5); trap over pre-bead folds (5-95% glow 0.07..0.48, no longer constant), tail-only;
  real near-miss halo from min SDF along missed rays; miss depth 0; head-up flip.
Camera check: map(ro) >= 2.33 for mouse extremes over t in [0,20]; fin 121 px @220x96 at default, visible from +/-yaw except
  when the camera orbits to the snout side (occluded, expected).
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha. JSON: +mouse-driven, +upgraded-rgba; params byte-exact.
REFUSED: none. Not verified on GPU.

STATUS: final
