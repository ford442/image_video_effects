SHADER: gen-neon-snowfall
IDENTITY: three parallax layers of chromatic neon snow falling through a dark sky, treble twinkle, per-flake motion-blur streaks, temporal streak persistence.
KEEP VERBATIM: 3-layer depth parallax loop, hash/palette flake colouring, bass_env smoothing, 6-step motion-blur trail, twinkle, temporal persistence mix, slider mappings (density 20..180, fall 0.08..2, chroma 0.2..2, streak 0..1).
ADD (2 native ideas):
  1. Nakaya crystal habit per falling column: hexagonal plates (with rib lines) <-> stellar dendrites (6 arms + 60-degree side branches tapering to the tip); mids = supersaturation pushes the habit toward dendrites; silhouette fades in once a cell is >= ~4-12 px, gaussian core otherwise.
  2. Habit-dependent fall dynamics: plates sink faster (terminal velocity 1.3x) and flutter wide/fast with a specular basal-face glint as the swing passes level; dendrites drift slowly (0.72x) with small flutter; flutter lateral velocity feeds the streak direction. Click ripples = radial wind gusts (near layer pushed most), mouse-held = eddy around the cursor.
FLOOR FIXES: extraBuffer[0] bass envelope relocated to guarded extraBuffer[133]; textureSampleLevel(dataTextureC) -> clamped exact textureLoad; A was (flake,trail,0,1) but read back as colour -> A now final ACES display RGBA, same as writeTexture; alpha was hardcoded 1.0 -> snow coverage (flakes+streaks+glints+luma); depth was 0 -> near-layer-weighted coverage; plasmaBuffer audio clamped 0..1; click ripples + mouse-held added (were missing); header/uniform comments; JSON features [] -> required three + params array.
FORBID: extraBuffer outside 133..138, dataTextureB writes, reading u.config.y/zw as audio, replacing flakes with generic noise.
A PACKING: ACES display RGBA in A
VERIFY: naga ok / gate ok / extraBuffer ok / sliders x,y,z,w live
