# Agent 4B: Audio Reactivity Specialist
## Task Specification - Phase B, Agent 4

**Role:** Audio-Driven Enhancement Engineer  
**Priority:** MEDIUM  
**Target:** Add audio reactivity to 50+ shaders  
**Estimated Duration:** 3-4 days

---

## Mission

Add audio reactivity to existing shaders and ensure audio-reactive features work correctly. Audio reactivity uses FFT (Fast Fourier Transform) data to make visuals respond to music/sound.

---

## Audio Input System

### How Audio Data Arrives

```wgsl
// Audio data is passed through uniforms
// Different fields may carry audio depending on shader category:

// Option 1: In config.y (common for generative shaders)
let audio = u.config.y; // 0.0 to 1.0 (overall magnitude)

// Option 2: In zoom_config.x (common for image/video shaders)
let audio = u.zoom_config.x;

// Option 3: Pre-processed bands in extraBuffer (if available)
let bass = extraBuffer[0];
let mid = extraBuffer[1];
let treble = extraBuffer[2];
```

### Audio Data Format

| Channel | Typical Content | Range |
|---------|----------------|-------|
| Raw | Overall FFT magnitude | 0.0 - 1.0 |
| Bass | 20-250 Hz | 0.0 - 1.0 |
| Mid | 250-4000 Hz | 0.0 - 1.0 |
| Treble | 4000-20000 Hz | 0.0 - 1.0 |

---

## Audio Reactivity Patterns

### Pattern 1: Bass Pulse
**Use for:** Rhythmic expansion/contraction effects

```wgsl
// Get bass frequencies
let bass = getAudioBass();

// Create rhythmic pulse
let pulse = 1.0 + bass * 0.5;

// Apply to UV coordinates (zoom effect)
uv = (uv - 0.5) / pulse + 0.5;

// Or apply to effect intensity
let effectStrength = baseStrength * pulse;
```

**Visual Effect:** Effect pulses with the beat of the music

---

### Pattern 2: Frequency-Based Color Shift
**Use for:** Color-cycling that responds to music

```wgsl
// Get frequency bands
let bass = getAudioBass();
let mid = getAudioMid();
let treble = getAudioTreble();

// Shift hue based on dominant frequency
let dominantFreq = select(
    select(0.0, 0.33, mid > treble), // Green
    0.66, // Blue
    bass > mid && bass > treble
);

// Or continuous shift based on overall energy
let hueShift = getAudioOverall() * 2.0;
color = hueShift(color, hueShift);

// Or tint based on frequency balance
let tint = vec3<f32>(bass * 1.5, mid * 1.0, treble * 2.0);
color = mix(color, color * tint, 0.5);
```

**Visual Effect:** Colors shift and respond to different instruments/vocals

---

### Pattern 3: Beat Detection
**Use for:** Triggering effects on beats

```wgsl
// Beat detection using threshold
let isBeat = step(0.7, getAudioBass());

// Flash on beat
let flash = isBeat * 0.3;
color += vec3<f32>(flash);

// Or trigger ripple
if (isBeat > 0.5 && prevBeat < 0.5) {
    triggerRipple(center, time);
}

// Or displace on beat
let displacement = isBeat * 0.1 * normalize(uv - center);
uv += displacement;
```

**Visual Effect:** Flashes, ripples, or displacements synchronized to beats

---

### Pattern 4: Spectral Visualization
**Use for:** Making the shader respond to specific frequency ranges

```wgsl
// Sample multiple frequency bands
for (var i = 0; i < NUM_BANDS; i++) {
    let freq = f32(i) / f32(NUM_BANDS);
    let magnitude = getAudioBand(i);
    
    // Visualize as vertical bars
    let barX = freq;
    let barHeight = magnitude;
    
    if (abs(uv.x - barX) < barWidth && uv.y < barHeight) {
        let barColor = frequencyToColor(freq);
        color = mix(color, barColor, magnitude);
    }
}
```

**Visual Effect:** Frequency spectrum overlaid or integrated into effect

---

### Pattern 5: Audio-Driven Displacement
**Use for:** Liquids, distortions, flow fields

```wgsl
// Audio as displacement strength
let audio = getAudioOverall();

// Create displacement field
let displacement = vec2<f32>(
    sin(uv.y * 10.0 + time) * audio,
    cos(uv.x * 10.0 + time) * audio
);

// Or use audio to drive noise
let noiseInput = uv * 5.0 + audio * 2.0;
let displacement = vec2<f32>(
    noise(noiseInput),
    noise(noiseInput + 100.0)
);

// Apply displacement
let displacedUV = uv + displacement * 0.1;
color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0).rgb;
```

**Visual Effect:** Distortion amount varies with music intensity

---

### Pattern 6: Temporal Audio Memory
**Use for:** Effects that "remember" recent audio

```wgsl
// Use feedback buffer to store audio history
// extraBuffer can store recent audio values

// Store current audio
extraBuffer[audioIndex] = currentAudio;

// Read historical audio
let delayedAudio = extraBuffer[(audioIndex - 30) % BUFFER_SIZE];

// Mix current and delayed
let mixedAudio = currentAudio * 0.7 + delayedAudio * 0.3;

// Advance index
extraBuffer[BUFFER_SIZE - 1] = f32((audioIndex + 1) % BUFFER_SIZE);
```

**Visual Effect:** Audio has "trail" or echo effect

---

## Target Shaders for Audio Reactivity

### High Priority (Most Impact)
- [ ] stellar-plasma
- [ ] gen-xeno-botanical-synth-flora
- [ ] tensor-flow-sculpting
- [ ] hyperbolic-dreamweaver
- [ ] liquid-metal
- [ ] voronoi-glass
- [ ] chromatic-manifold
- [ ] infinite-fractal-feedback
- [ ] ethereal-swirl
- [ ] gen-audio-spirograph (verify/improve)

### Medium Priority (Good Enhancement)
- [ ] quantum-superposition
- [ ] kimi_liquid_glass
- [ ] crystal-refraction
- [ ] holographic-* shaders
- [ ] neon-* shaders
- [ ] vortex-* shaders
- [ ] gen-voronoi-crystal
- [ ] gen-supernova-remnant
- [ ] gen-string-theory
- [ ] plasma

### Generative Shaders (Natural Fit)
- [ ] All new generative from Phase A
- [ ] All new generative from Phase B
- [ ] gen-neural-fractal
- [ ] gen-mycelium-network
- [ ] gen-magnetic-field-lines
- [ ] gen-bifurcation-diagram

---

## Implementation Templates

### Template 1: Basic Audio Reactivity

```wgsl
// Add to existing shader

// ═══ AUDIO INPUT ═══
let audioOverall = u.config.y; // or u.zoom_config.x
let audioBass = audioOverall * 1.5; // Approximation if no bands available

// ═══ AUDIO-MODULATED PARAMETERS ═══
let speed = mix(0.5, 2.0, u.zoom_params.x) * (1.0 + audioOverall * 0.5);
let intensity = u.zoom_params.y * (1.0 + audioBass);
let scale = 1.0 + audioOverall * 0.3;

// Use in effect
let animatedUV = uv + vec2<f32>(sin(time * speed), cos(time * speed)) * 0.1;
```

### Template 2: Frequency-Based

```wgsl
// If extraBuffer has frequency bands
let bass = extraBuffer[0];
let mid = extraBuffer[1];
let treble = extraBuffer[2];

// Different effects for different frequencies
let bassEffect = bass * 0.5;
let midEffect = mid * 0.3;
let trebleEffect = treble * 0.2;

// Combine
let totalEffect = bassEffect + midEffect + trebleEffect;
```

### Template 3: Beat Sync

```wgsl
// Detect beat
let beatThreshold = 0.6;
let isBeat = step(beatThreshold, audioBass);

// Beat-reactive color
let beatColor = vec3<f32>(1.0, 0.8, 0.5) * isBeat * 0.5;
color += beatColor;

// Beat-reactive displacement
let beatDisplacement = normalize(uv - 0.5) * isBeat * 0.05;
```

---

## Shader Modification Guide

### Step 1: Identify Parameter to Modulate

Look for:
- Animation speed (`time * speed`)
- Effect intensity/strength
- Color saturation/brightness
- Displacement amount
- Scale/zoom factors

### Step 2: Add Audio Input

```wgsl
// At top of main function
let audio = u.config.y; // Adjust based on shader type
let audioBass = audio * 1.2;
```

### Step 3: Modulate Parameters

```wgsl
// BEFORE
let speed = mix(0.5, 2.0, u.zoom_params.x);

// AFTER
let speed = mix(0.5, 2.0, u.zoom_params.x) * (1.0 + audio * 0.5);
```

### Step 4: Add Beat Effects (Optional)

```wgsl
// Add flash on strong beats
let isBeat = step(0.7, audio);
color += vec3<f32>(isBeat * 0.2);
```

### Step 5: Update JSON

```json
{
  "features": ["audio-reactive", "existing-feature"],
  "tags": ["audio", "music", "existing-tag"]
}
```

---

## Deliverables

1. **50+ upgraded shader files** with audio reactivity
2. **Documentation:** Audio integration guide
3. **Pattern library:** Reusable audio-reactive code snippets

---

## Success Criteria

- 50+ shaders have audio reactivity added
- Audio response is smooth (not jittery)
- Effect is musically coherent (responds to beat, not noise)
- Performance maintained (audio read is cheap)
- All existing functionality preserved
- JSON definitions updated with "audio-reactive" feature

---

## Testing Notes

When testing audio reactivity:
1. Test with different music genres (bass-heavy, treble-heavy)
2. Test with silence (should still work)
3. Test with constant tone (should respond smoothly)
4. Verify no audio = minimal effect (not zero/broken)
