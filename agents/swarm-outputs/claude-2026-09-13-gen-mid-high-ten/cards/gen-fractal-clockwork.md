# Idea Card — gen-fractal-clockwork

```
SHADER: gen-fractal-clockwork
IDENTITY: an infinite raymarched checkerboard of counter-rotating brass gears on a floor, orbited by a sprung mouse camera.
KEEP VERBATIM: sdGear (sin-tooth cylinder with axle bore), repeated-cell map with parity-alternating direction, 96-step raymarch,
  shade() brass/steel/gold material thresholds, zoom_params roles (x gear scale, y teeth, z rotation speed, w material),
  sprung orbit camera in extraBuffer[133..138], click-torque ripple rings, temporal C blend, chromatic dispersion.
EXISTING IDEAS (2026-09-06): 1. gear-tooth crest sparks; 2. inter-gear mesh line.
ADD:
  3. Dead-beat escapement tick — gears advance one tooth pitch per tick on top of their continuous turn (stop-go
     stepping fed into map() so geometry, sparks and shading stay in sync), with a brass flash on the tick; native
     because an escapement is literally what makes clockwork tick.
  4. Ruby jewel bearings — a jewel ring around each axle bore on the gear faces with a sharp glint whose
     intensity follows bass; native because real clock movements run their pivots in ruby jewels.
FORBID: IQ cosine palette, new spring/ripple systems (the existing ones stay as-is), fractal/creature swaps,
  holographic scanlines, extra conveyors.
A PACKING: ACES display RGBA (C read back via exact textureLoad as colour history) — unchanged.
```

## Notes

- Kept verbatim: sdGear, parity-alternating cell map, 96-step raymarch, shade() material thresholds, four slider roles, sprung orbit camera (extraBuffer[133..138]), click-torque rings, ideas 1–2, chromatic dispersion, C blend, alpha/depth logic. JSON `params`/`updatedParams` byte-exact.
- A packing: ACES display RGBA in A; C read with exact `textureLoad` as colour history (unchanged).
- Idea locations (public/shaders/gen-fractal-clockwork.wgsl): Idea 3 escapement offset in map() L64, tick phase/esc/tickFlash computed in main L142–148 and passed through raymarch/normals/tGear, tick flash L193–194; Idea 4 ruby jewel ring + glint L195–201. Existing ideas 1–2 at L185/L189.
- Escapement step = pi/teeth (exactly one tooth period of the sin tooth profile), so `fract()` wraps seamlessly with no float growth; gated by rotation-speed slider so speed 0 still means stopped.
- Floor: audio was already plasmaBuffer[0].xyz and ACES already present; banner Features was dishonest — now lists audio-reactive, upgraded-rgba. JSON features gained "audio-reactive" and "mouse-driven" (orbit camera follows pointer). No dead sliders, no hardcoded alpha, no reserved identifiers found.
- Gates: naga "Validation successful"; wgsl_precommit_gate --files 1/1 passed, 0 extraBuffer violations; no textureStore(dataTextureC.
- Real-GPU visual QA: external.
