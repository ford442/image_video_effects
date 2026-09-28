```
SHADER: gen-chromatic-singularity-loom
IDENTITY: thin cylinder threads repeated by a fold-and-rotate loop, pulled by a 1/r^2 gravity warp toward a
  mouse-placed singularity sphere, coloured by a chromatic lensing term with accretion glow/bloom.
KEEP VERBATIM: rot, map structure (thread cylinder length(pos.xz)-0.05, fold/rotate loop, singularity sphere,
  L51-85), gravity warp 1/r^2 concept (L57-63), chromatic shift term, accretion glow, ACES (L37,87), slider families
  (x mass, y fold/weave, z accretion glow, w chromatic shift; applyGenerativePrimaryControls may be kept), saved params.
FIX/WIRE (major first):
  - HEAD BLACK AFTER ~0.1 s: plasma_index = min(u32(dist*10 + time*10), 255u) (L139) reads plasmaBuffer[1..255]
    (zero / OOB) -> plasma_color = 0 -> col = 0. Replace with a real colour source (the existing chromatic lensing term
    driven by dist/time, tinted by plasmaBuffer[0].xyz).
  - y fold count i32(y) (L66-68): y in (0,1) -> 0 iterations at the default 0.5 (no weave); y=0 -> 4. Map to a
    continuous count (e.g. 2 + y*4 with fractional blend).
  - audio_intensity = u.config.y (L104) is rippleCount -> plasmaBuffer[0]; mid unused.
  - Gravity warp uses normalize(pos) (L63) = direction from the ORIGIN, not from center, unbounded mass/dist^2 ->
    use pos-center, clamp the pull, scale step (relaxation) for the non-Lipschitz map. Centre mouse -> no NaN.
  - rot(time*0.2*chaos) (L74) audio/click-scaled time -> phase from time only.
  - C read with textureSampleLevel + sampler (L159) and only on hit pixels -> exact textureLoad, every pixel.
  - Depth dO/MAX_DIST (L167) inverted -> near 1, miss 0.
  - Mouse y inverted (L54/L137 flip vs unflipped uv L102): flip uv so screen top = +y and make mouse consistent.
  - The ==0 slider substitutions (L57, L142, L152) are fine to keep (saved defaults are 0.5).
ADD (native ideas):
  1. Spaghettification necking — fuse warp and threads: thread radius (0.05) and brightness follow the local warp
     strength mass/dist^2 at that point, so threads visibly neck thin and stretch as they fall toward the singularity
     and fatten far away.
  2. Warp/weft parity — map() already returns a material channel (L84) that nobody reads. Record the fold index /
     parity of the nearest thread inside the fold loop and shade even/odd families as two thread colours (warp vs
     weft), so the folded threads read as a woven loom.
  3. (optional) Orbital accretion trail — read C exactly at a coordinate rotated slightly around the projected
     singularity (Keplerian-like angular advection, faster near the centre) and blend with a real weight (HEAD's
     ~2.4% is invisible), so light spirals in toward the singularity.
FORBID: photon ring, Doppler beaming, gravitational redshift, lensed far-side halo, singularity shadow, self-assembling
  sectors, time dilation (sibling gen-bismuth-singularity-loom-engine), heddle lanes, plasma shuttle, over-under
  interlacing, thread thin-film, IQ palette as the whole look.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (HEAD already stores pre-ACES in A).
DEFAULT-LOOK SHIFT: HEAD black after 0.1 s and 0 folds at default; now a visible woven thread field. Not GPU-verified.
```

STATUS: superseded by Final below

## Final (implementer, 2026-09-27)

Audit claims verified against HEAD — all TRUE:
- Black frame: L139-140 `plasmaBuffer[min(u32(dist*10+time*10),255)]` reads slots 1..255 (zero / OOB) -> col = 0 once time > 0.1 s.
- y fold count `i32(y)` = 0 on 0<y<1 (default 0.5 -> no folds, one straight thread hidden in the sphere).
- audio_intensity = config.y (rippleCount); mids unused. Warp used normalize(pos) from the ORIGIN, unclamped.
- Phase rot(time*0.2*chaos) audio-scaled; C via textureSampleLevel on hits only; depth dO/MAX_DIST inverted.
- Extra: uv.y was not flipped AND mouse scaled by 10 (singularity ran off-screen and moved opposite on y). Fixed both.

FIX (floor): warp from (pos - center), pull clamped at 2.5, r->0 safe (L66-74); continuous 2..6 folds blended
  floor/ceil (L80-121); weave phase = time*0.2*y only (L86; 0.1 rad/s at default = HEAD's audio-0 rate), audio is an
  additive angle jitter; step relaxed by 1/r^2 gradient bound + grazing-hit rule (L166-181); audio from plasmaBuffer[0];
  singularity projected under the pointer on z=0 (L157-162); plasma lookup replaced by warm glow tint + plasmaBuffer[0]
  (L207-209); exact textureLoad of C on every pixel; depth near 1 / miss 0 (L241-242). ==0 substitutions for x/z/w kept.
Numpy port (scratchpad port.py): map(camera) 0.03..2.07 > 0 for x,y in {0,0.25,0.5,0.75,1}, 3 mouse positions, 2 clocks;
  default 47-76% of rays hit, 0 stalled; worst 2.6% stalled at x=0 (mass 2). Warp/weft split ~50/50.

Ideas as implemented:
  1. Tidal spaghettification — threadR = 0.07/(1+4*pull) in map (L76-78, 0.057 far -> 0.023 at pull 0.5); striation
     frequency 14/(1+6*pull) stretches + brightness (1+1.5*pull) in shading (L211-217).
  2. Mirror-parity warp/weft — reflection count in the fold loop (L98-100), parity -> material 1/2 (L113-121, map's
     unused material channel now read); weft hue phase +PI and 0.8 brightness (L195-198, L218-219).
  3. Orbital infall trail — exact C at pixel rotated by 0.035/(r+0.15) rad and scaled 1.012 about the projected
     singularity, max-blended with decay 0.8..0.92 (strongest near the singularity) (L225-236). Replaces HEAD's ~2.4% memory.
Audio (not ideas): bass -> mass pulse / R lensing / trail decay; mids -> fold offset, angle jitter, bloom; treble -> B lensing; xyz -> glow tint.
A PACKING: HDR linear RGB (pre-ACES) + semantic alpha (luminance coverage); ACES only on writeTexture (applyGenerativePrimaryControls kept).
Refused/skipped: none; no ripples/spring added (HEAD had none). JSON: features = upgraded-rgba, audio-reactive, mouse-driven; params byte-exact.
DEFAULT-LOOK SHIFT: HEAD black after 0.1 s; now a dense woven field of complementary two-family threads necking toward
  a glowing sphere under the pointer, with light spiralling in. Mouse now tracks the singularity. Not GPU-verified.

STATUS: final
