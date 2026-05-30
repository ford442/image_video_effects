# cinematic-flare — New Shader Notes

## Overview
New anamorphic lens flare effect. Horizontal streaks emanate from bright image regions with chromatic separation.

## Algorithm
- Samples 16 points horizontally from each pixel
- Accumulates color weighted by brightness above threshold (bloom detection)
- Chromatic streaks: R channel extends further on bass, B on treble
- Depth-aware: near objects emit stronger flares
- Gold tint added by mids

## Wow Factor
- Cinematic Hollywood look with authentic anamorphic streaks
- Audio makes flares pulse and change color with the music

## Risks
- 16 texture samples per pixel is expensive
- Bloom threshold may need tuning for different content brightness
