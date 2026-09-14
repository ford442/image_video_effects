# Idea Card — gen-liquid-metal-cymatic-resonator

```
SHADER: gen-liquid-metal-cymatic-resonator
IDENTITY: a fixed-camera, raymarched silver heightfield pool whose surface is a polar Fourier sum of standing waves
  (radial sin x angular cos) forming a cymatic mandala, perturbed by the pointer, with grazing-angle thin-film iridescence.
KEEP VERBATIM: mapHeight polar standing-wave series (resonance base freq, complexity harmonic count, 1/(1.5 i) falloff,
  central peak, smax floor, *0.2 scale), mouse frequency perturbation, getNormal, fixed camera (0,2.5,-2.5), 100-step
  half-step heightfield march, getEnvColor sky + sun, iridescence(), Schlick fresnel f0=0.8, grazing iridescence mix,
  flat-pool darkening by viscosity, gamma. Param roles: x Resonance, y Viscosity, z Iridescence, w Complexity.
EXISTING IDEAS: none named (first idea pass).
ADD:
  1. Real viscosity drag — the file's own comment says Viscosity "can't read history" and fakes it with darkening;
     now the display blends with exact textureLoad(dataTextureC) history weighted by Viscosity (thicker metal =
     slower-settling reflections), keeping the existing pool darkening. Native: it is the slider's literal meaning.
  2. Chladni nodal crystallization — where the standing-wave sum crosses zero relative to its local slope (nodal
     lines of the cymatic plate) the metal "crystallizes" into thin bright filigree with a sharper, cooler specular;
     treble adds glints along the nodes. Native: the description promises crystallizing mandala patterns, and nodal
     lines are exactly where real cymatic sand/particles gather.
  3. Ferrofluid Rosensweig spikes under the pointer — the existing mouse perturbation also raises a small hexagonal
     spike field (ferromagnetic liquid under a magnet) whose height follows bass. Native: the description says
     ferromagnetic liquid and the pointer already acts as the field source.
FORBID: spring cursor, u.ripples shockwaves, IQ cosine palette, conveyors, camera orbit, replacing the Fourier
  heightfield or the iridescence model, dataTextureB.
A PACKING: display RGBA (post-ACES, post-gamma) in A; C read back via exact textureLoad as colour history.
  (HEAD sampled C.r with a filtering call and treated it as "audio" — that was a packing lie; audio now plasmaBuffer[0].)
```
