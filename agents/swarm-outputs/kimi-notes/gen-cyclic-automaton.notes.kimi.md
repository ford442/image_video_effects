# gen-cyclic-automaton — Batch 2 Upgrade Notes

## Changes Made
- Added chromatic aberration before inline ACES in textureStore
- Used `let chromaticColor = vec3<f32>(...)` to avoid reassigning `let finalColor`
- Preserved CA simulation logic and decodeState temporal reads

## Validation
- naga: ✅ pass
