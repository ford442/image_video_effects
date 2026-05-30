# digital-reveal — Kimi Batch E Notes

## Changes Made
- Added chromatic drops: bass shifts green channel, treble shifts white highlights
- Added depth-reveal: near objects reveal faster via `depthReveal` scalar
- Added audio-reactive rain speed: treble accelerates drop fall
- Added audio-reactive density: bass scales rain density
- Temporal mask persistence via `dataTextureC`

## Wow Factor
- Digital rain now pulses with the beat — bass makes drops greener and faster
- Depth-reveal means foreground objects emerge first from the rain

## Risks
- `depthReveal` multiplies mask value; very near objects may reveal instantly (too fast)
- Treble speed multiplier may make rain look like static at high values
