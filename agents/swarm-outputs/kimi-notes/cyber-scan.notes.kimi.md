# cyber-scan — Kimi Batch E Notes

## Changes Made
- Added temporal scan pass: previous frame smears vertically for persistence
- Added depth colorize: near = warm orange scan, far = cool cyan scan
- Added chromatic scan: treble shifts RGB channels horizontally
- Added audio-reactive scan speed: bass scales speed via `bass_env()`
- Added bass-driven scan width expansion

## Wow Factor
- Scan line leaves a colored trail that persists like phosphor burn-in
- Depth-based colorization makes foreground objects glow warmly

## Risks
- Vertical smear from `dataTextureC` may blur image significantly at high trail values
- Chromatic shift per treble may cause color fringing on fast scans
