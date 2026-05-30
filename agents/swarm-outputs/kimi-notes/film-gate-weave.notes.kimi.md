# film-gate-weave — New Shader Notes

## Overview
Authentic analog 16mm film artifacts: gate weave, dust, scratches, color flicker.

## Algorithm
- Frame ID derived from time * 24fps
- Vertical gate weave: slow sine drift + per-frame hash jitter
- Audio bass adds extra jitter
- Dust: sparse random dots seeded by frame
- Scratches: vertical lines with frame-random placement
- Per-frame RGB color flicker via hash
- Mids add sepia warmth

## Wow Factor
- Genuinely feels like old film stock running through a projector
- Audio jitter makes the film feel unstable

## Risks
- Frame-locked artifacts may stutter if frame rate != 24fps
- Dust density at max may cover too much image
- Gate weave shifts image out of frame at high values
