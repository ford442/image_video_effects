# New Shader Effects Documentation

This document describes the two new shader effects added to the image/video effects application.

## 1. Fractal Kaleidoscope

**ID**: `fractal-kaleidoscope`  
**Category**: Image Effect  
**File**: `public/shaders/fractal-kaleidoscope.wgsl`

### Description

A mesmerizing fractal kaleidoscope effect that creates infinite mirrored patterns with rotating symmetry. The effect combines multiple visual techniques to create a psychedelic, ever-evolving display.

### Visual Effects

- **Kaleidoscope Mirroring**: Creates symmetrical patterns by mirroring the image across rotating segments
- **Dynamic Segments**: Number of mirror segments animates between 4 and 8 over time
- **Multi-Level Fractal Zoom**: Applies 3-5 iterations of fractal zoom based on depth
- **Chromatic Aberration**: RGB channels are slightly offset to create a prism-like effect
- **Depth Awareness**: Foreground objects get more complex fractal iterations
- **Symmetry Glow**: Adds glowing highlights along symmetry lines
- **Interactive Ripples**: Mouse clicks create wave patterns that propagate through the kaleidoscope

### Technical Features

```wgsl
// Key functions:
- rotate2D(): 2D rotation transform for kaleidoscope
- kaleidoscopeFractal(): Creates mirrored segments
- fractalZoom(): Multi-level zoom with rotation
```

### Parameters

- **Segments**: 6 ± 2 (animated with sine wave)
- **Iterations**: 3 to 5 (based on depth)
- **Chromatic Offset**: 0.003 units
- **Zoom Speed**: 0.3 + depth × 0.2

### Use Cases

- Psychedelic music visualizations
- Abstract art generation
- Meditation/relaxation visuals
- Experimental photography effects
- VJ loops and live performance visuals

---

## 2. Digital Waves

**ID**: `digital-waves`  
**Category**: Image Effect  
**File**: `public/shaders/digital-waves.wgsl`

### Description

A cyberpunk-inspired digital distortion effect that simulates glitchy, retro-futuristic video processing. Combines wave distortion, RGB splitting, scanlines, and digital artifacts for a distinctive aesthetic.

### Visual Effects

- **Digital Wave Distortion**: Multi-layer sine wave displacement
- **RGB Channel Split**: Separate red, green, and blue channels along wave angles
- **Scanlines**: Retro CRT monitor scanline effect (300 lines)
- **Glitch Blocks**: Random rectangular regions with position offsets
- **Pixelation**: Depth-aware pixel block effect
- **Color Quantization**: Reduces colors to 16 levels (posterization)
- **Cyan/Magenta Shifts**: Temporal color channel biasing
- **Digital Pulse**: Concentric circle pulses on mouse click
- **Film Grain**: Subtle noise overlay

### Technical Features

```wgsl
// Key functions:
- hash21(): Pseudo-random number generation
- digitalWavePattern(): Multi-layer wave synthesis
- scanlines(): CRT scanline rendering
- pixelate(): Block pixelation effect
- rgbSplit(): Chromatic aberration along angles
- glitchBlocks(): Random glitch artifacts
```

### Parameters

- **Wave Speed**: 2.0 units/second
- **Wave Frequency**: 15 + depth × 10
- **Scanline Frequency**: 300 Hz
- **Pixel Size**: 0.001 to 0.004 (depth-based)
- **Color Levels**: 16 (4-bit color)
- **Glitch Probability**: 5% per block

### Use Cases

- Cyberpunk/sci-fi aesthetics
- Retro video game effects
- Glitch art and vaporwave visuals
- Digital distortion effects
- Technical/hacker aesthetic
- VHS/analog video simulation
- Electronic music visualizations

---

## Integration

Both shaders are registered in `public/shader-list.json` and can be selected from the shader dropdown menu.

### Shader List Entries

```json
{
  "id": "fractal-kaleidoscope",
  "name": "Fractal Kaleidoscope",
  "url": "shaders/fractal-kaleidoscope.wgsl",
  "category": "image",
  "description": "Mesmerizing fractal kaleidoscope with depth-aware multi-level zoom...",
  "features": ["depth-aware", "interactive", "fractal", "chromatic-aberration"]
}
```

```json
{
  "id": "digital-waves",
  "name": "Digital Waves",
  "url": "shaders/digital-waves.wgsl",
  "category": "image",
  "description": "Cyberpunk digital wave distortion with RGB split...",
  "features": ["depth-aware", "temporal-persistence", "interactive", "glitch", "cyberpunk"]
}
```

## Performance

Both shaders are optimized for real-time performance:

- **Fractal Kaleidoscope**: Medium GPU load (iterative transforms)
- **Digital Waves**: Medium GPU load (multiple texture samples for RGB split)

Both run at 60 FPS on modern GPUs (2020+).

## Compatibility

- Requires WebGPU support
- Works with both image and video inputs
- AI depth map enhances effects but is not required
- Mouse interaction supported

## Future Enhancements

### Fractal Kaleidoscope
- Adjustable segment count parameter
- Color palette selection
- Fractal iteration depth control
- Zoom speed parameter

### Digital Waves
- Adjustable glitch intensity
- Scanline frequency control
- Color quantization level parameter
- Wave pattern selection (sine, square, sawtooth)

---

*These shaders expand the collection from 39 to 41 effects, providing new creative options for users.*
