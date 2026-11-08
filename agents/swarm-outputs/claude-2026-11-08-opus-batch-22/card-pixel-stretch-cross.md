SHADER: pixel-stretch-cross
IDENTITY: Fibonacci-ray pixel stretch toward the cursor with trails + crossing bloom
KEEP VERBATIM: ray family, gravity well, axis/velocity steering, bloom, alpha layering, param ids
ADD:
  1. Stepped pixel runs — smear source snaps to blocks along each ray (block length grows with distance, bass shortens)
  2. Fringed streak tips — R/G/B stretched by 1, f, f² along the ray
  3. Cross glints — four-point star on hot crossings, arm lengths follow axisMix
RESCUES:
  - A stored (smoothBass, crossMask, 0, a) but C.rgb was fed back as the trail colour → whole smear washed red/yellow/green. A now = trail RGB + alpha.
  - Mouse velocity lived in extraBuffer[0..3] (CPU re-uploaded) → "velocity" = mouse position; moved to state texels (0,0)/(1,0) with sentinel -7, bass envelope too.
  - JSON params names were legacy (H/V Stretch, Depth, Turbulence); renamed to live roles, bloom default 0.5→0.3 to match x-meta. Ids kept.
Stats (256px, 20f, t=3): idle meanL .512 (tinted wash) → .518 legible image; held+audio .520 red wash → .623 image + smear.
Open: stepped runs subtle at 256px.
