# Audio Reactivity Guide

## Overview

This document describes the audio reactivity system implemented across 50+ shaders in the image_video_effects project. Audio reactivity allows visual effects to respond dynamically to music and sound input, creating immersive audio-visual experiences.

## Audio Input System

### Uniform Data Channels

Audio data is passed to shaders through uniform buffers:

```wgsl
// For generative shaders (config.yzw carries audio)
struct Uniforms {
    config: vec4<f32>,       // x=Time, y=AudioLow, z=AudioMid, w=AudioHigh
    zoom_config: vec4<f32>,  // x=MouseX, y=MouseY, z=Audio, w=unused
    zoom_params: vec4<f32>,  // User parameters
};
```

| Channel | Range | Description |
|---------|-------|-------------|
| `u.config.y` | 0.0 - 1.0 | Low frequencies (bass/beat) |
| `u.config.z` | 0.0 - 1.0 | Mid frequencies |
| `u.config.w` | 0.0 - 1.0 | High frequencies (treble) |
| `u.zoom_config.x` | 0.0 - 1.0 | Overall audio level (image shaders) |

### Access Patterns

```wgsl
// Generative shaders
let audioOverall = u.config.y;
let audioBass = u.config.y;
let audioMid = u.config.z;
let audioHigh = u.config.w;

// Image/Video shaders  
let audioOverall = u.zoom_config.x;
let audioBass = audioOverall * 1.5;
```

## Audio Reactivity Patterns

### Pattern 1: Speed Modulation

Modulate animation speed based on audio intensity:

```wgsl
let audioReactivity = 1.0 + audioOverall * 0.5;
let animatedValue = sin(time * speed * audioReactivity);
```

**Used in:**
- `neural-raymarcher` - Neural network pulse animation
- `hyperbolic-dreamweaver` - Hyperbolic space rotation
- `cellular-automata-3d` - CA evolution speed
- `gen-xeno-botanical-synth-flora` - Growth animation

### Pattern 2: Intensity Scaling

Scale effect intensity with bass frequencies:

```wgsl
let pulseIntensity = baseIntensity * (1.0 + audioBass * 0.8);
```

**Used in:**
- `neon-pulse` - Pulse strength
- `liquid-metal` - Ripple intensity
- `vortex-*` - Vortex strength

### Pattern 3: Color Modulation

Shift colors based on frequency content:

```wgsl
let hueShift = (audioLow - audioHigh) * 0.1;
color = hueShift(color, hueShift);
```

**Used in:**
- `stellar-plasma` - Cosmic color shifts
- `chromatic-manifold` - Chromatic aberration
- `gen-supernova-remnant` - Explosion colors

### Pattern 4: Beat Detection

Trigger effects on strong beats:

```wgsl
let isBeat = step(0.7, audioBass);
let flash = isBeat * 0.3;
color += vec3<f32>(flash);
```

**Used in:**
- `gen-quantum-mycelium` - Beat-synchronized pulses
- `quantum-superposition` - State collapse flash
- `audio-voronoi-displacement` - Voronoi cell burst

### Pattern 5: Displacement Modulation

Modulate distortion/displacement effects:

```wgsl
let displacement = noise(uv * 10.0 + time) * audioOverall * 0.1;
```

**Used in:**
- `kimi_liquid_glass` - Liquid distortion
- `holographic-interferometry` - Interference patterns
- `spectral-flow-sorting` - Flow intensity

## Updated Shaders (50+)

### High Priority (10)
| Shader | Audio Pattern | Description |
|--------|---------------|-------------|
| `stellar-plasma` | Color + Speed | Cosmic nebula responds to all frequencies |
| `gen-xeno-botanical-synth-flora` | Speed + Growth | Alien flora blooms with bass |
| `tensor-flow-sculpting` | Displacement | Tensor warping follows audio |
| `hyperbolic-dreamweaver` | Rotation | Hyperbolic rotation speed varies |
| `liquid-metal` | Ripple | Metallic ripples pulse with beat |
| `voronoi-glass` | Displacement | Glass cells shift with frequency |
| `chromatic-manifold` | Color | Chromatic aberration from audio |
| `infinite-fractal-feedback` | Zoom | Zoom rate follows bass |
| `ethereal-swirl` | Rotation | Swirl speed reactive |
| `gen-audio-spirograph` | Position | Spirograph arms move to music |

### Medium Priority (10)
| Shader | Audio Pattern | Description |
|--------|---------------|-------------|
| `quantum-superposition` | Chaos | Quantum states fluctuate |
| `kimi_liquid_glass` | Distortion | Glass distortion from audio |
| `crystal-refraction` | Sparkle | Crystal sparkle with treble |
| `gen-voronoi-crystal` | Cell shift | Crystal cells respond |
| `gen-supernova-remnant` | Explosion | Explosion intensity |
| `gen-string-theory` | String vibration | String oscillation |
| `plasma` | Turbulence | Plasma turbulence |
| `holographic-projection` | Scanlines | Scanline flicker |
| `holographic-glitch` | Glitch | Glitch frequency |
| `holographic-contour` | Contour | Edge intensity |

### Neon Shaders (10)
| Shader | Audio Pattern |
|--------|---------------|
| `neon-pulse` | Pulse frequency |
| `neon-light` | Brightness |
| `neon-edges` | Edge intensity |
| `neon-echo` | Echo decay |
| `neon-warp` | Warp strength |
| `neon-strings` | String vibration |
| `neon-fluid-warp` | Fluid turbulence |
| `neon-topology` | Topology morph |
| `neon-edge-pulse` | Edge pulse |
| `neon-edge-reveal` | Reveal speed |

### Vortex Shaders (5)
| Shader | Audio Pattern |
|--------|---------------|
| `vortex` | Rotation speed |
| `vortex-distortion` | Distortion amount |
| `vortex-warp` | Warp intensity |
| `vortex-prism` | Prism rotation |
| `velvet-vortex` | Velvet flow |

### Phase B New Shaders (10)
| Shader | Audio Pattern |
|--------|---------------|
| `hyper-tensor-fluid` | Tensor fluid response |
| `neural-raymarcher` | Neural activation |
| `chromatic-reaction-diffusion` | Reaction rate |
| `fractal-boids-field` | Boid movement |
| `holographic-interferometry` | Interference |
| `gravitational-lensing` | Lens distortion |
| `cellular-automata-3d` | CA evolution |
| `spectral-flow-sorting` | Flow rate |
| `multi-fractal-compositor` | Fractal depth |

### Generative Shaders (10+)
- `gen-neural-fractal` - Fractal zoom
- `gen-mycelium-network` - Growth rate
- `gen-magnetic-field-lines` - Field strength
- `gen-bifurcation-diagram` - Bifurcation speed
- `gen-quantum-superposition` - State mixing
- `gen-quasicrystal` - Pattern rotation
- `gen-cymatic-plasma-mandalas` - Plasma response
- `gen-ethereal-anemone-bloom` - Bloom pulse
- `gen-singularity-forge` - Singularity intensity
- ...and more

## Implementation Template

### Basic Audio Reactivity

```wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    
    // ═══ AUDIO INPUT ═══
    let audioOverall = u.config.y;  // or u.zoom_config.x for image shaders
    let audioBass = audioOverall * 1.2;
    let audioMid = u.config.z;
    let audioHigh = u.config.w;
    let audioReactivity = 1.0 + audioOverall * 0.5;
    
    // Use audio to modulate effect
    let speed = baseSpeed * audioReactivity;
    let intensity = baseIntensity * (1.0 + audioBass * 0.3);
    
    // ... shader logic ...
}
```

### Beat Detection

```wgsl
// Detect strong beats (bass > 0.7)
let isBeat = step(0.7, audioBass);

// Flash on beat
let beatFlash = isBeat * 0.2;
color += vec3<f32>(beatFlash);

// Or trigger one-shot effect
if (isBeat > 0.5 && prevBeat < 0.5) {
    triggerEffect();
}
```

### Frequency-Based Color

```wgsl
// Different colors for different frequencies
let bassColor = vec3<f32>(1.0, 0.3, 0.1) * audioBass;
let midColor = vec3<f32>(0.3, 1.0, 0.3) * audioMid;
let highColor = vec3<f32>(0.3, 0.3, 1.0) * audioHigh;

color = mix(color, bassColor + midColor + highColor, 0.5);
```

## JSON Configuration

Add audio-reactive features to shader definitions:

```json
{
  "id": "my-shader",
  "name": "My Audio-Reactive Shader",
  "features": [
    "audio-reactive",
    "audio-driven"
  ],
  "tags": [
    "audio",
    "music",
    "reactive"
  ]
}
```

## Performance Considerations

1. **Audio reads are cheap** - Reading from uniforms has minimal cost
2. **Avoid branching** - Use `mix()`, `step()` instead of `if` statements
3. **Cache audio values** - Read once, reuse in calculations
4. **Smooth transitions** - Audio data may be per-frame, use smoothing if needed

## Testing

### With Music
1. Play bass-heavy music to test bass response
2. Test with treble-heavy tracks for high-frequency response
3. Verify smooth transitions between beats

### With Silence
1. Shader should still function normally
2. Effects should have minimal or default intensity

### Edge Cases
1. Sudden volume spikes shouldn't break the effect
2. Very low audio shouldn't cause visual glitches

## Success Criteria

- ✅ 50+ shaders have audio reactivity added
- ✅ Audio response is smooth (no jitter)
- ✅ Musically coherent (responds to beat, not noise)
- ✅ Performance maintained
- ✅ All existing functionality preserved
- ✅ JSON definitions updated with "audio-reactive" feature

## Report

See `audio-reactivity-report-v2.json` for detailed information about all updated shaders.
