# Coordinator review — Densest Crystal/Chrome Nine (2026-09-27)

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9: card before diff; each idea pointable (`// Idea N` tags + header `Ideas:`);
KEEP VERBATIM holds; diff not boilerplate-dominated; no shared overlay; A packing matches C read; saved params exact;
springs/ripples only if native (none added); naga + precommit + extraBuffer + dead sliders.

| Shader | Ideas found in WGSL | Params | A packing | Verdict |
|---|---|---|---|---|
| gen-bismuth-hyper-crystals | nucleation seed (foldOff near gSeed), fractional fold growth (dN/dN1 mix), fold-lineage palette offset | exact | HDR + alpha, C 0.12 blend | PASS |
| gen-celestial-nanite-swarm-nebula | Kuramoto/Adler closed-form blink, lattice-edge docking of feature points, face-dust Beer-Lambert | exact | ACES display (HEAD), C unread | PASS |
| gen-chromatic-singularity-loom | tidal necking threadR(pull), mirror-parity warp/weft (flip count), orbital infall C trail | exact | HDR + alpha, C exact every pixel | PASS |
| gen-chrono-kitsune-prism-weaver | per-tail spectral band + body rim dispersion, heartbeat along tails, fractional tail unfurl | exact | HDR + alpha (HEAD) | PASS |
| gen-chronodynamic-aether-weaver-automata | coupled Rule 90 tooth rings (bounded 24-step stateless), capstan wrap along gear SDF | exact | HDR + alpha (was packing lie) | PASS |
| gen-crystalline-chrono-dyson | statite swarm (polar repetition, 2 SDFs), quasar->spoke->conduit packets, louvred panels | exact | clamped HDR + alpha (HEAD) | PASS |
| gen-crystalline-nebula-weaver-void-spider | nebula-gated web nodes, 8-leg tetrapod gait, spinneret dragline | exact | HDR + alpha (HEAD) | PASS |
| gen-cybernetic-crystalline-neuro-lattice | nucleation front via existing blend, per-cell memory bits (Glitch), light-piped links | exact | HDR + alpha (HEAD) | PASS |
| gen-cybernetic-liquid-chrome-engine | V8 1-8-4-3-6-5-7-2 crank (table checked), compression-ignition crush + TDC flash, heat shimmer on C fetch | exact | HDR + alpha (HEAD) | PASS |

Spot checks done by the coordinator (read the idea regions, not just the reports):
- chrome: firePos table (0,7,3,2,5,4,6,1) indexed by cylinder matches the 1-8-4-3-6-5-7-2 order; audio scales stroke only.
- kitsune: FFT read `extraBuffer[4u+k]` for k=1..8 = bins [5..12] (correct, not off-by-one).
- nanite: Adler closed form θ = 2·atan((K + w·tan(wτ/2))/Δω) is the right solution of dθ/dt = Δω − K sin θ.
- automata: toothAutomaton is bounded (≤ CA_EPOCH-1 = 23 steps), uniform per frame; not a hidden state claim.
- No file added a spring cursor, ripple rings or an IQ palette stamp; no two files share an idea.

Accepted deviations (documented in cards):
- Slider-scaled time kept where HEAD had it (bismuth z, nanite z, dyson z, chrome y, automata y): a jump-free speed
  control needs persistent state, and extraBuffer is zeroed every frame. Audio no longer enters any phase.
- JSON descriptions rewritten honestly for automata (was empty) and spider (claimed a spring cursor / carapace that
  did not exist). Kitsune's untrue "chrono-void lattice" wording was left as-is (flag for a later pass).
- Kitsune tails now splay outward (at HEAD they ran straight behind the body: 0 tail hits in the numpy port).
- Automata planet gear now also spins on its axle so the teeth truly mesh (needed for the bit hand-off).
- Neuro-lattice crystal half-box 0.3 -> 0.1 (0.3 filled ~96% of space; HEAD was blank/NaN).

Gates: naga 9/9, wgsl_precommit_gate 9/9, audit:extrabuffer PASS, dead-slider audit PASS (1305 scanned; chrome agent
saw 0 scanned in its run and checked by hand), params/updatedParams byte-exact 9/9, check_duplicates clean.
Real-GPU visual QA: external — nothing here is visually verified.
