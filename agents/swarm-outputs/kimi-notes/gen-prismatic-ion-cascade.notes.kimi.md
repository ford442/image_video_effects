# gen-prismatic-ion-cascade — Kimi Notes

## Changes
- Temporal cascade persistence: `dataTextureC` ion trail burns in at 8–11% for glowing stream afterimages.
- Audio-driven stream count: `bass` adds up to 4 extra radial streams dynamically.
- Bass radial pulse enhancement: core falloff breathes with low-frequency audio.
- Depth-scaled ion intensity: `readDepthTexture` attenuates distant cascade bands.

## Wow-Factor
- Ion streams that leave persistent glowing trails — like radioactive water flowing from the mouse cursor.
- Bass spikes thicken the cascade in real time, creating explosive radial bursts.

## Risks
- `fbm` called twice per pixel (warp + shimmer); 5 octaves each = 10 noise evaluations.
- Temporal persistence can saturate colors quickly if bass is sustained high; blend factor is clamped.
