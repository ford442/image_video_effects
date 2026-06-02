# vinyl-scratch — Kimi Batch E Notes

## Changes Made
- Added chromatic wobble: R and B channels wobble at different rates
- Added depth-groove: depth scales groove noise intensity
- Added audio-reactive rotation: bass drives spin speed
- Added audio-reactive warping: mids warp the record
- Added treble-driven groove noise
- Dynamic alpha from groove intensity + bass

## Wow Factor
- Wobbling vinyl now separates RGB like a warped prism
- Bass literally spins the record faster

## Risks
- Chromatic wobble adds 2 extra texture samples per pixel
- Workgroup size changed from (8,8,1) to (16,16,1) for standard occupancy
