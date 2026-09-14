SHADER: gen-prismatic-aether-loom
IDENTITY: Warp-flight through a KIFS-braided cylindrical thread lattice with thin-film iridescence, velocity-aligned spectral streaks, click shuttle waves and radially advected braid trails.
KEEP VERBATIM: kifsFold, fbm/noise3D cosmic wind, cylinder lattice map, raymarch loop, palette thin-film, speed lines, click shuttle ripple loop, fog, radial trail advection.
ADD (2 native ideas):
  1. Plain-weave over-under interlacing: weft (X) and warp (Y) threads undulate in z with opposite cosine phase so every crossing passes over/under; amplitude bass-breathed and capped at 8% of spacing for SDF safety.
  2. Snell-refracted thin-film thread sheath (n=1.38) evaluated at 650/532/450 nm; thickness from Chromatic Shift + mids, treble shimmer along thread length; blended 45% with the existing palette film.
FLOOR FIXES: header replaced (removed COPY PASTE junk); plasmaBuffer split into clamped bass/mids/treble (map() read clamped); A now receives the same ACES display RGBA as writeTexture (was HDR) and C history decoded via analytic ACES inverse (/1.2 gain) so trails keep their strength; mouse uv remapped to the centered uv frame (was 2x off); mouse-held tightens braid twist and boosts shuttle-wave alpha; features + params array added.
FORBID: dataTextureB writes, extraBuffer use, config.y/zw as audio, replacing the loom motif.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
