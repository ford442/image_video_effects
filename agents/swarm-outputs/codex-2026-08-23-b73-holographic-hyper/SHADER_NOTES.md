# Batch 73 feedback ownership and shader notes

## A/C payloads

- Fracture, Plasma Geode, Rainbow Surface, Hopf Fiber Bundle, Bismuth
  Clockwork, Bismuth Matrix, and Tesseract Labyrinth store exact ACES display
  RGBA in A/C. Previous display pixels are loaded exactly and are never sent
  through ACES a second time.
- Lens-Flare Matrix stores raw `[density, streak, nearestDistance, alpha]`.
- Holographic Membrane stores raw `[height, normalX, normalY, alpha]`.
- Hyper Labyrinth stores raw HDR neon RGB plus semantic wall/vein alpha. Its
  display path alone is tone-mapped.

`dataTextureB` is declared for binding compatibility but never written. C is
read only through integer `textureLoad`. Only Fracture writes guarded spring
state at `[133..137]`; Bismuth Matrix writes its guarded bass envelope at
`[133]`. Both use invocation `(0,0)` as the sole writer. Hyper Labyrinth no
longer reads engine FFT slots.

## Interaction and audio

All ten distinguish pointer hover/position, held behavior, and click events.
Click loops are capped by `min(u32(u.config.y), 50u)` and reject negative or
expired timestamp ages. Bass, mids, and treble have separate motion, geometry,
lighting, color, or detail roles in every shader.

## Saved controls

The original ten `updatedParams` arrays are byte-equivalent by parsed value.
Holographic Fracture retains its existing four parameter IDs. The other nine
definitions add four named `params` entries aligned one-to-one with x/y/z/w and
their established labels, defaults, ranges, and steps.
