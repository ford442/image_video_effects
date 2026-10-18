# Cursor batch-06 — coordinator review

2026-10-18. Cards were written before the diff.

| Shader | Ideas in the diff | Keep holds | Packing | Verdict |
|---|---|---|---|---|
| spectrogram-displace-pass1 | Hann sidelobes; peak-hold; live bin ink | synth, four palettes, four slider roles | raw `(color.rgb, magnitude)` | pass |
| spectrogram-displace-pass2 | spectral shear; raster bin ticks | RGB displacement, boosts, vignette, bass | does not write A; ACES on writeTexture | pass |
| spectrogram-displace | harmonic stack; differential waterfall decay | FFT mix, scroll, spring, clicks | ACES display RGBA | pass |
| gen-magnetic-field-lines | equatorial current sheet; polar cusp | LIC, X-point, helices, mirror | ACES display RGBA | pass |
| gen-quantum-foam-alpha | pair worldline; one-sigma shell | pairs, flashes, Born hits, membranes | raw vacuum tuple | pass |
| gen-sonic-lava-flow | channel levees; a'a clinker | cooling skin, pahoehoe, curl | linear color history | pass |
| gen-cybernetic-liquid-chrome-engine | oil gallery; head bolts | crank, cam notches, blueing | pre-ACES HDR | pass |
| magnetic-dipole | magnet body; chain links | sprites, packets, pole-flip, A channels | `(fieldDir.xy, alignment, fieldStrength)` | pass |
| gen-cybernetic-ferro-coral | corallite cup; septa | spikes, Turing bands, circuit, pulse | ACES display history | pass |
| gen-fluffy-raincloud | fallstreak hole; crepuscular shafts | anvil, mammatus, shelf, virga | raw density / velocity / moisture | pass |

Formula names: none of the §12.2 rows are shared. The spectrogram ideas are device artifacts of a waterfall display, not a copied glitch overlay. Magnetic ideas are dipole geometry, not a second LIC. Lava ideas extend the existing flow direction and shear.

- [x] Mechanism interrogation is in `BRIEFS.md`
- [x] Each idea is marked in WGSL
- [x] Saved params unchanged
- [x] No spring added to a shader that did not already own the pointer
- [x] Pass 2 no longer clobbers the field
- [x] Naga 10/10, precommit 10/10, extraBuffer clean, dead sliders clean on the definitions the scanner reads

Real-GPU visual QA: external.
