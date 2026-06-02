# elastic-strip — Kimi Upgrade Notes

## Changes
- Spring physics strips with bass-driven oscillation frequencies
- Depth-based stiffness: foreground strips are stiffer
- Chromatic stretch: R/B channels offset by stretch magnitude × treble
- Edge glow on strip boundaries driven by mids
- Audio frequency response per strip via `sin(freq + bass)`

## Wow Factor
- Strips vibrate like guitar strings plucked by bass
- Chromatic edge bleeding makes stretched areas look like prisms

## Risks
- Spring oscillation can alias at low frame rates
- Horizontal/vertical switch param needs UI label clarity
