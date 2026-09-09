# Wet media / charcoal / ink / paint ten — Idea Cards (written before WGSL)

Family: charcoal on paper, impasto thickness, sumi-e / Gray-Scott ink, Navier–Stokes ink, watercolor wetness, oil Kuwahara. Quiet native ideas. No spring+ripple+IQ stamp. No Wave Halftone ellipse+rosette. No watercolor-bloom granulation+backrun clone. Springs none (HEAD had none). `mouse-ink-bleed` extraBuffer[0..7] left alone.

---

SHADER: charcoal-rub
IDENTITY: mouse rubs charcoal onto laid paper; image reveals as density builds
KEEP VERBATIM: hardness / texture_scale / reveal_rate / fade_speed; paper fbm; mouseDown brush; C.r reveal mask
ADD:
  1. Laid-paper fiber catch — grain is stretched along a paper-fiber axis so charcoal nests in valleys (rubbing, not a hatch overlay)
  2. Vine-dust halo — faint particles just outside the stick radius (vine charcoal, not click brands)
FORBID: springs, IQ palettes, converting this into ink wash or oil impasto
A PACKING: raw reveal in A.r (HEAD); G/B unused; do not ACES stored mask

---

SHADER: charcoal-rub-diffusion
IDENTITY: Perona-Malik smooths the photo, then charcoal reveal draws it
KEEP VERBATIM: hardness / texture / reveal / diffusion_strength; Perona-Malik kappa/dt; mouse heat boost; charcoal conversion
ADD:
  1. Contour vine strokes — charcoal density follows the Sobel of the diffused luma (drawing along edges)
  2. Kneaded-eraser skip — high-luma diffused regions resist charcoal (highlight reserve)
FORBID: springs, cloning charcoal-rub’s fiber stretch as the whole upgrade, extra CA
A PACKING: raw reveal in A.r (HEAD)

---

SHADER: alpha-paint-thickness
IDENTITY: accumulating pigment with thickness in alpha; wash → body → impasto specular
KEEP VERBATIM: pigment.rgb + thickness in A; mouse hue brush; click splatters; wash/medium/thick/ridge path
ADD:
  1. Palette-knife ridge — highlights run along the thickness gradient (knife, not random sparkle)
  2. Canvas tooth in thin wash — weave shows through low thickness
FORBID: springs, replacing thickness with a liquid solver, IQ palette
A PACKING: raw pigment.rgb + thickness.a (HEAD). Wire saved specularPower / dryingRate (z/w). Exact C neighbor loads.

---

SHADER: ink-diffusion
IDENTITY: sumi-e ink in water with curl advection, vorticity, surface tension, paper fiber
KEEP VERBATIM: spread / decay / turbulence / density; laplacian + curl + vorticity; wet-edge spec; ACES; A=(ink, vel.xy, alpha)
ADD:
  1. Fiber-steered advection — paper-fiber anisotropy turns the curl (ink follows laid paper)
  2. Nijimi bloom — extra laplacian only on the wet edge (sumi feather, not watercolor granulation)
FORBID: springs, Gray-Scott rewrite, cloning watercolor-bloom
A PACKING: raw ink/vel (HEAD). Exact C loads (was textureSample on C).

---

SHADER: sim-ink-diffusion
IDENTITY: three-channel Gray-Scott ink (coral / fingerprint / spots) on paper
KEEP VERBATIM: wetness / viscosity / feed / colorMixing; Wolfram F/k triples; U in rgb, V in A.a; paperTexture
ADD:
  1. Anisotropic paper laplacian — lap stretched along fiber (still Gray-Scott, not a new RD)
  2. Coffee-ring pile-up — V concentrates where |∇U| is high (dry-front ring)
FORBID: rewriting the three patterns, k-cyclic, springs
A PACKING: raw U.rgb + V.r in A.a (HEAD). Wire viscosity into Du/Dv.

---

SHADER: ink-bleed-fluid
IDENTITY: Navier–Stokes velocity/pressure with ink density in A; mouse injects ink+force
KEEP VERBATIM: hue / viscosity / spread / density; vel.rg pressure.b ink.a; Jacobi; vorticity; mouse/ripple inject
ADD:
  1. Paper capillary — valleys absorb and spread ink; peaks damp velocity
  2. Wet-edge darkening — density gradient feathers a darker rim (bleed, not CA)
FORBID: new springs, IQ candy as the look, rewriting the solver
A PACKING: raw vel/pressure/ink (HEAD). Exact C loads. ACES display only.

---

SHADER: mouse-paint-splatter
IDENTITY: drag splatters sample the photo, wet paint spreads and dries; clicks burst
KEEP VERBATIM: splatterSize / dryRate / spread / colorIntensity; sample-at-mouse color; 4-neighbor wet spread; click shaped splash; (0,0) mouse stash
ADD:
  1. Cast-off satellites — extra droplets along the stroke tangent from mouseVel
  2. Dry craquelure — hash cracks appear as wetness falls (drying paint, not glitch)
FORBID: springs, replacing splatters with a fluid solver
A PACKING: paint.rgb + wetness.a (HEAD). Keep (0,0) mouse stash. Exact C loads for paint.

---

SHADER: alpha-fluid-simulation-paint
IDENTITY: packed NS paint (vel.xy, pressure, dye) with audio viscosity
KEEP VERBATIM: viscosity / dyeBrightness / vorticity / decay; Jacobi; vorticity confinement; mouse/ripple dye; ACES
ADD:
  1. Dye-front surface tension — velocity pulls toward high density
  2. Impasto lighting from density gradient (paint height, not extra CA)
FORBID: paper-capillary clone of ink-bleed-fluid, springs, IQ palette as the whole look
A PACKING: raw vel/pressure/dye (HEAD)

---

SHADER: alpha-watercolor-wetness
IDENTITY: pigment flows with a water field; wet bleeds, dry locks; mouse drops color
KEEP VERBATIM: dryRate / pigmentDeposit / waterCap; water gravity; advection; existing granulation/backrun/haze
ADD:
  1. Cockling warp — photo UVs buckle from the water Laplacian (wet paper, not a new sim)
  2. Salt bloom — pale flecks where water is leaving (drying crystals, not granulation)
FORBID: treating existing granulation/backrun as the upgrade; springs
A PACKING: raw pigment.rgb + water.a (HEAD). Wire flowStrength (w). Exact C loads.

---

SHADER: artistic_painterly_oil
IDENTITY: anisotropic Kuwahara oil with quantized body, impasto height, wet specular, canvas weave
KEEP VERBATIM: brush_size / wetness / levels / impasto; 4-sector Kuwahara; height lighting; canvas mix
ADD:
  1. Scumble skip — thin paint misses canvas peaks (dry-brush)
  2. Wet-in-wet from exact C — previous body mixes where wetness is high (oil, not a new solver)
FORBID: springs, replacing Kuwahara with ink dots, IQ palette
A PACKING: pre-ACES color.rgb + thickness.a (HEAD wrote display color into A; C unused — now read as wet-in-wet body). ACES writeTexture only.
