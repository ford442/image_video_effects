# Fireworks shell taxonomy ten — Idea Cards (written before WGSL)

Family: leftover catalog fireworks with named shell geometry (chrysanthemum / dahlia / crossette / crackle-palm / willow / horse-tail / kamuro / ring / strobe / roman candle). August 23 already did bindings/ACES/exact-C/four named params — that is the floor, not this upgrade. Two native pyrotechnic ideas each. Identities kept. Existing pointer command shells kept; Roman Candle click-ripple tubes kept; no new extraBuffer springs.

Claimed IDs: `gen-fireworks-chrysanthemum`, `gen-fireworks-dahlia-burst`, `gen-fireworks-crossette`, `gen-fireworks-crackle-palm`, `gen-fireworks-willow-cascade`, `gen-fireworks-horse-tail`, `gen-fireworks-kamuro-gold`, `gen-fireworks-ring-shell`, `gen-fireworks-strobe-shell`, `gen-fireworks-roman-candle`.

Skipped: `gen-fireworks-audio-symphony` (extraBuffer[133] bass envelope), `gen-fireworks-nocturne` (composite mortar field), `gen-fireworks-wind-ripple`, `gen-fireworks-smoke-bloom`, `gen-fireworks-comet-trail`, `gen-fireworks-fan-shell`. Did not take holographic leftovers, kaleido/tunnel, classic fractals, hybrid lattice, Batch 71 mycelium/DMT/cymatic.

---

SHADER: gen-fireworks-chrysanthemum
IDENTITY: dense spherical peony / chrysanthemum burst with concentric timed ring layers and inner/outer color
KEEP VERBATIM: burstSize / ringLayers / density / colorSpread; ring-layer stagger; chrysanthemumColor; radial streak; ascent rocket; mouse peony
ADD (2 native ideas):
  1. Pistil heart — innermost ring slower and denser than outer rays (kiku heart, not another layer delay stamp)
  2. Sphere foreshorten — ring positions use a z-phase so layers read as a ball, not a flat disk
FORBID on this file: extra palm crackle, strobe, springs
A PACKING: ACES display RGBA (HEAD stores color history in A; C is previous display)

---

SHADER: gen-fireworks-dahlia-burst
IDENTITY: flat petal-disk dahlia shell with layered petal rows
KEEP VERBATIM: petalCount / diskSize / petalRows / hueCycle; dir/perp petals; hex bokeh; row delay; mouse dahlia
ADD (2 native ideas):
  1. Imbrication — even rows rotate by half a petal so rows nest, not stack
  2. Midrib — thin bright line along each petal’s dir
FORBID on this file: turning it into a spherical peony; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-crossette
IDENTITY: four-arm split burst — primary flash then cardinal children
KEEP VERBATIM: power / splitDly / armSpread / hueShift; 4 cardinal arms; armColor; mouse four-arm
ADD (2 native ideas):
  1. Parent then fork — a primary star flies, then four children spawn from THAT star at splitDly (not four independent offset centers)
  2. Split-instant X flash at the fork
FORBID on this file: 8-arm rewrite, palm stages, springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-crackle-palm
IDENTITY: three-stage shell — primary burst, delayed crackle, palm fronds
KEEP VERBATIM: energy / stageDelay / crackleAmt / palmSpread; addCrackle; addPalmFrond; mouse triple-stage
ADD (2 native ideas):
  1. Crackle born on primary spark positions, not random subCenters
  2. Opposite leaflet pairs on each frond
FORBID on this file: a fourth stage; willow as the whole look; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-willow-cascade
IDENTITY: long gravity-drooping golden/silver willow curtain
KEEP VERBATIM: trailLen / droopAmt / windAmt / warmth; willowPos; 5-sample trail; wind slider; mouse willow
ADD (2 native ideas):
  1. Terminal hang at strand tips — curtain settles, does not keep accelerating
  2. Leeward lean of the whole curtain from the existing wind term
FORBID on this file: kamuro glitter cloud; horse-tail parallel rain; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-horse-tail
IDENTITY: narrow terminal-velocity gold brocade streamers
KEEP VERBATIM: tailLen / spread / gold / fall; drag-integrated sparkPos/tailPos; shell gust; stream width; mouse brocade
ADD (2 native ideas):
  1. Brocade pinch — streamers start in a tight cluster then fall as parallel rain
  2. Tip spark-out — gold cuts off at the streamer end (not a willow charcoal fade)
FORBID on this file: claiming Batch 37 drag/sway as this upgrade; willow curtain; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-kamuro-gold
IDENTITY: slow-hanging gold/silver glitter snowstorm
KEEP VERBATIM: density / fallSpd / goldMix / hang; kamuroPos hang; dense glitter; gold/silver mix; mouse shower
ADD (2 native ideas):
  1. Independent twinkle per glitter (not one shell pulse)
  2. Hang plateau — after hang time, sparks pause then resume fall
FORBID on this file: willow streaks; horse-tail streamers; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-ring-shell
IDENTITY: crisp Saturn-ring / donut halo front
KEEP VERBATIM: ringR / thick / count / colorC; ring spark loop; mouse halo
ADD (2 native ideas):
  1. Saturn tilt — ring is an inclined ellipse, not a face-on circle
  2. Empty core — suppress sparks inside ringR − thick (true halo; today’s inner jewels fill the hole)
FORBID on this file: filling as a peony; treating existing palette() as the upgrade; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-strobe-shell
IDENTITY: multi-flash blink shell before color fall
KEEP VERBATIM: flashRate / pulsePow / afterglow / colorFlash; strobePulse; afterglow embers; afterglow slider as trail mix
ADD (2 native ideas):
  1. Per-spark flash phase so the shell is many blinking stars, not one sine
  2. True dark interval (pulse can hit 0). No floor(time) hash strobe
FORBID on this file: making it a continuous peony; springs
A PACKING: ACES display RGBA

---

SHADER: gen-fireworks-roman-candle
IDENTITY: fixed-tube star barrage (not an aerial shell)
KEEP VERBATIM: fireRate / starSize / tubeSpread / trailLen; tubes; shot interval; apex mini-burst; held mouse + click ripples
ADD (2 native ideas):
  1. Muzzle flash at the tube mouth on each shot
  2. Per-tube color sequence (shot 0,1,2 cycle the existing starCol set)
FORBID on this file: turning it into an aerial shell; new springs
A PACKING: ACES display RGBA
