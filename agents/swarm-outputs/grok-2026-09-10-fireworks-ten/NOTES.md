# Fireworks shell taxonomy ten — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `gen-fireworks-chrysanthemum` | burstSize / ringLayers / density / colorSpread; ring stagger; chrysanthemumColor; radial streak; mouse peony | `pistil` slower/denser inner ring; `lat` / `ringR3` / `yLift` sphere foreshorten | ACES display RGBA |
| `gen-fireworks-dahlia-burst` | petalCount / diskSize / petalRows / hueCycle; dir/perp petals; hex bokeh; row delay | `imb` even-row half-petal; `rib1`/`rib2` midrib | ACES display RGBA |
| `gen-fireworks-crossette` | power / splitDly / armSpread / hueShift; 4 cardinal arms; armColor | parent `sparkPos` then children from `fork`; X flash at split | ACES display RGBA |
| `gen-fireworks-crackle-palm` | energy / stageDelay / crackleAmt / palmSpread; addCrackle; addPalmFrond | crackle `hostPos` = primary spark; opposite `leaf` pairs | ACES display RGBA |
| `gen-fireworks-willow-cascade` | trailLen / droopAmt / windAmt / warmth; willowPos; 5-sample trail | hangT terminal grav; `burstLean` leeward curtain | ACES display RGBA |
| `gen-fireworks-horse-tail` | tailLen / spread / gold / fall; drag sparkPos/tailPos; shell gust | pinch `dir.x*0.22` + `parallel` rain; `sparkOut` tip cut | ACES display RGBA |
| `gen-fireworks-kamuro-gold` | density / fallSpd / goldMix / hang; kamuroPos; gold/silver | `tw` per-glitter; hang `plateauStart` freeze then resume | ACES display RGBA |
| `gen-fireworks-ring-shell` | ringR / thick / count / colorC; ring spark loop | `tilt` ellipse; `onHalo` empty core (inner jewels removed) | ACES display RGBA |
| `gen-fireworks-strobe-shell` | flashRate / pulsePow / afterglow / colorFlash; afterglow mix | `strobePulse(..., phase)`; `pow(wave, 10)` dark interval | ACES display RGBA |
| `gen-fireworks-roman-candle` | fireRate / starSize / tubeSpread / trailLen; tubes; apex burst; mouse + click ripples | muzzle at tube mouth; `seq` cycles starCol | ACES display RGBA |

No new extraBuffer springs. Roman Candle click ripples kept. Saved `params` unchanged. JSON `"upgraded-rgba"` added after ideas; strobe `features` gained audio-reactive + mouse-driven + upgraded-rgba.

Skipped: audio-symphony, nocturne, wind-ripple, smoke-bloom, comet-trail, fan-shell.
