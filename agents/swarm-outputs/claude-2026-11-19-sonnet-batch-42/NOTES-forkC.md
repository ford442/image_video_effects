# NOTES — fork C (gen-celestial-nanite-swarm-nebula, gen-quantum-pollen)

Box load 20+ throughout (other forks): nanite ran 4.6–16 s/frame at 192 on SwiftShader; all timings noise.

## gen-celestial-nanite-swarm-nebula (second pass)
- HEAD render (defaults 0.5,0.3,0.2,0.7): one docked lattice box centre-frame + faint web; meanL 0.10 idle / 0.10 held. Not broken; no rescue.
- Header `Ideas:` listed 2 of 5 in-code ideas — added the 3 missing (Kuramoto sync, lattice docking, Beer-Lambert face dust) verbatim-in-spirit; earlier 2 kept verbatim. `Upgraded:` appended 2026-11-19. A packing unchanged.
- Idea 6 Henyey-Greenstein backlit dust (§12.2 HG phase, row assigned): hidden beacon star up-right behind the swarm; face dust in-scatters it with g=0.85, attenuated by Beer-Lambert trans. Visibility @192: 54 % px, mean|Δ| 0.107 (measured at gain 0.45; shipped 0.3).
- Idea 7 Flash relay across shared Voronoi faces (native): Kuramoto blink × face-dust emits magenta along shared faces (outside the d>0.01 branch — first attempt inside it measured 0.0 %). @192: 61 %, mean 0.074. Scales with Constellation Link.
- 576 visibility runs did not finish under load — open.
- meanL idle 0.10→0.22, held 0.10→0.22, audio →0.41; nan 0. Gates: precommit ✓, naga-wasm ✓, dead-sliders 0, extrabuffer no findings.
- frameMs 96px 4 rounds: nanite perf rounds appended at end of file (median ~1.0×, load noise).

## gen-quantum-pollen (second pass)
- HEAD render: full-frame RGB pixel speckle (no grains readable), worse at large time. Two causes confirmed by reading + render at T0=900:
  - Rescue 1: swarmDensity mix(8,82) on top of warpScale≈3.25 → 60–230 cells across frame, grains sub-pixel. Now mix(2,9) (slider still density, 0→1 changes meanL 0.15→0.20).
  - Rescue 2: `drift * time` with a SPATIAL drift (vortex/gravity/burst) shears the grid without bound as time grows. Only uniform drift is now integrated over time; spatial fields displace the lookup (`offset`).
- Idea 3 curl-noise anther eddies (§12.2 curl-noise advection, assigned): divergence-free curl of 2-octave fbm displaces grains AND the feedback advection. 74.6 % px @192 and @576, mean 0.22.
- Idea 4 anemophilous gust fronts (native): diagonal travelling wind band thickens haze ×(1+2.5g), golden cloud tint, pushes grains along wind. 9.5 % @192, 9.6 % @576.
- Earlier ideas (exine spikes, tetrad dehiscence) kept verbatim. A packing unchanged.
- meanL idle 0.179→0.179, held 0.222→0.227, audio 0.415; nan 0. All 4 sliders sweep visibly. Gates ✓ (precommit, naga-wasm, dead-sliders 0, extrabuffer).
- perf 192, 4 rounds: ratios 2.22/1.40/1.01/0.47 → median ≈1.2 (load noise ±2×; coordinator re-time). Cost added: 4 fbm(2) for curl.
- JSON untouched for both (tags already true).
round 1 head=2524.30 new=1591.50 ratio=0.63
round 2 head=1468.80 new=1932.50 ratio=1.316
round 3 head=1782.00 new=1477.90 ratio=0.829
round 4 head=1505.80 new=1726.10 ratio=1.146
