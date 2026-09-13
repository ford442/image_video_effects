# Fireworks leftover atmospheric six — notes

Per shader: kept verbatim, packing, ideas in the diff.

| ID | Kept | Ideas in WGSL | Packing |
|---|---|---|---|
| `gen-fireworks-fan-shell` | fan-angle / shell-power / spark-density / hue-cycle; rocket then fan; mouse fan; Batch 37 drag / shellWind / flutter / stars | `palmette` even=outer/odd=inner 0.55; `eyeGate` cooler ocellus at mid-age | ACES display RGBA |
| `gen-fireworks-comet-trail` | comet-speed / trail-length / head-brightness / color-shift; 7 comets; peel; late burst; mouse comet | `ionTail` straight anti-velocity; coma `softGlow` around head (hex core kept) | ACES display RGBA |
| `gen-fireworks-smoke-bloom` | smokeDensity / bloomStrength / burstEnergy / trailDecay; smokePuff; mouse peony; neighbor bloom | `puffCenter` y += burstAge*0.12; `flashLit` scales puff | ACES display RGBA |
| `gen-fireworks-wind-ripple` | windEnergy / rippleSensitivity / trailLength / colorDrift; sparkPosWind; click-ripple barrages; mouse | `altitudeShear`; `leeward` step(downwind) streak | ACES display RGBA |
| `gen-fireworks-nocturne` | energy / tempo / density / color-drift; 9 mortars; mouse command | muzzle at `launchPos`; `droopHabit` even round / odd vy*0.55 + extra grav | ACES display RGBA |
| `gen-fireworks-audio-symphony` | launch-density / bass-drive / mids-layering / treble-sparkle; extraBuffer[133] envelope; mouse | `idleEnergy`/`onsetEnergy` gated by bassPulse; `starTint` bass gold / mids rose / treble white | ACES display RGBA; [133] envelope |

Floor (not ideas): nocturne dropped unused `u.config.y` as `dt`. No new extraBuffer springs. Wind-ripple click ripples kept. Saved `params` unchanged. JSON `"upgraded-rgba"` added after ideas; smoke-bloom `features` was empty and gained audio-reactive + mouse-driven + upgraded-rgba.

Catalog 1,363 includes origin mycelium (#1241), not a new ID from this batch.
