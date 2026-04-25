# Temporal & Simulation Shader Techniques

Supplemental guide for creating motion-aware and multi-pass simulation effects.

---

## Part 1: Temporal / Motion-Aware Effects

### Concept
Temporal effects go beyond single-frame processing by maintaining state across frames, creating rich, evolving visuals that respond to motion and time.

---

### Technique 1: Frame Differencing for Motion Detection

Detect motion by comparing current frame with previous frame.

```wgsl
// In bindings: readTexture = current, dataTextureC = previous frame

fn detectMotion(uv: vec2<f32>) -> vec2<f32> {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    
    // Luminance of each frame
    let currLuma = dot(current, vec3<f32>(0.299, 0.587, 0.114));
    let prevLuma = dot(previous, vec3<f32>(0.299, 0.587, 0.114));
    
    // Calculate motion magnitude
    let diff = abs(currLuma - prevLuma);
    
    // Estimate motion direction from gradient
    let pixel = 1.0 / u.config.zw;
    let right = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;
    
    let dx = dot(right - left, vec3<f32>(0.299, 0.587, 0.114)) * 0.5;
    let dy = dot(up - down, vec3<f32>(0.299, 0.587, 0.114)) * 0.5;
    
    // Motion vector (approximate)
    return vec2<f32>(dx, dy) * diff * 10.0;
}
```

---

### Technique 2: Motion Trail / Smear

Create trails behind moving objects by accumulating and decaying.

```wgsl
// Multi-pass approach:
// Pass 1: Trail accumulation buffer
// Pass 2: Composite

// PASS 1: Accumulate trails
fn accumulateTrails(uv: vec2<f32>, time: f32) -> vec4<f32> {
    // Read current motion
    let motion = detectMotion(uv);
    let motionStrength = length(motion);
    
    // Read previous trail buffer (from dataTextureA)
    let prevTrail = textureLoad(dataTextureA, vec2<i32>(uv * u.config.zw), 0);
    
    // Current frame color
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    
    // Add current to trail where motion is high
    let contribution = current * motionStrength * 2.0;
    
    // Decay previous trail
    let decayRate = 0.95; // Tune this
    let decayed = prevTrail * decayRate;
    
    // Combine
    let trail = max(decayed, contribution);
    
    return trail;
}

// PASS 2: Composite with current frame
fn compositeWithTrails(uv: vec2<f32>) -> vec4<f32> {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let trail = textureLoad(dataTextureA, vec2<i32>(uv * u.config.zw), 0);
    
    // Trail color (can tint based on velocity)
    let trailColor = trail.rgb * vec3<f32>(1.0, 0.8, 0.6); // Warm trail
    
    // Screen blend or additive
    return current + trail * 0.5;
}
```

---

### Technique 3: Datamosh-Style Interframe Corruption

Create glitch effects by mixing pixels from previous frames based on motion.

```wgsl
fn datamoshEffect(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let motion = detectMotion(uv);
    let motionStrength = saturate(length(motion) * 5.0);
    
    // Read current and previous
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    
    // Displace sampling based on motion
    let blockSize = 0.02;
    let blockUV = floor(uv / blockSize) * blockSize;
    let blockMotion = detectMotion(blockUV);
    
    // Randomly sample from previous frame at displaced location
    let hashVal = hash12(blockUV + time);
    let usePrevious = step(0.7 - motionStrength * 0.3, hashVal);
    
    let displacedUV = uv + blockMotion * 0.5;
    let previousSample = textureSampleLevel(dataTextureC, u_sampler, displacedUV, 0.0).rgb;
    
    // Mix based on motion and randomness
    return mix(current, previousSample, usePrevious * motionStrength);
}
```

---

### Technique 4: Velocity-Sensitive Bloom

Apply bloom only to moving areas.

```wgsl
fn velocityBloom(uv: vec2<f32>) -> vec3<f32> {
    let motion = detectMotion(uv);
    let velocity = length(motion);
    
    // Only bloom if velocity above threshold
    let threshold = 0.1;
    let bloomAmount = smoothstep(threshold, threshold + 0.2, velocity);
    
    // Simple multi-sample bloom
    var bloom = vec3<f32>(0.0);
    let samples = 8;
    for (var i = 0; i < samples; i++) {
        let angle = f32(i) * 6.28318 / f32(samples);
        let offset = vec2<f32>(cos(angle), sin(angle)) * 0.02;
        bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
    }
    bloom /= f32(samples);
    
    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    return mix(base, bloom, bloomAmount * 0.5);
}
```

---

### Technique 5: Multi-Layer Echo Chamber

Create multiple delayed echoes of the video.

```wgsl
// Uses dataTextureA and dataTextureB for echo history
// Cycle through 4-8 echo buffers

const ECHO_COUNT: i32 = 4;

fn echoChamber(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    var result = current * 0.4; // Current frame weight
    
    // Read echoes from history
    let echo1 = textureLoad(dataTextureA, vec2<i32>(uv * u.config.zw), 0).rgb;
    let echo2 = textureLoad(dataTextureB, vec2<i32>(uv * u.config.zw), 0).rgb;
    
    // Each echo tinted differently
    result += echo1 * 0.3 * vec3<f32>(1.0, 0.9, 0.8); // Warm
    result += echo2 * 0.2 * vec3<f32>(0.8, 0.9, 1.0); // Cool
    
    // Rotate color for oldest echo
    result += echo2 * 0.1 * vec3<f32>(0.9, 1.0, 0.8); // Different tint
    
    return result;
}

// Update echo buffers each frame:
// echo2 = echo1 (shift back)
// echo1 = current (newest)
// Store in dataTextureA/B for next frame
```

---

## Part 2: Multi-Pass Simulation Effects

### Concept
Multi-pass simulations create "small visual worlds" that evolve over time, with physics-like behaviors that feel alive and organic.

---

### Technique 6: Simplified Navier-Stokes Fluid

2D fluid simulation using multiple passes.

```wgsl
// PASS 1: Advect velocity
@compute @workgroup_size(16, 16, 1)
fn advectVelocity(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    let pixel = 1.0 / u.config.zw;
    
    // Read velocity at current position
    let vel = textureLoad(dataTextureA, gid.xy, 0).xy;
    
    // Find where this velocity came from (backtrace)
    let prevPos = uv - vel * pixel * 2.0;
    
    // Sample velocity from previous position
    let advectedVel = textureSampleLevel(dataTextureC, u_sampler, prevPos, 0.0).xy;
    
    // Add curl noise for turbulence
    let curl = curlNoise(uv * 5.0 + u.config.x * 0.1);
    let newVel = advectedVel + curl * 0.01;
    
    // Damping
    newVel *= 0.995;
    
    textureStore(dataTextureA, gid.xy, vec4<f32>(newVel, 0.0, 1.0));
}

// PASS 2: Advect density (ink/dye)
@compute @workgroup_size(16, 16, 1)
fn advectDensity(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    let pixel = 1.0 / u.config.zw;
    
    // Read velocity
    let vel = textureLoad(dataTextureA, gid.xy, 0).xy;
    
    // Backtrace
    let prevPos = uv - vel * pixel * 2.0;
    
    // Advect density
    var density = textureSampleLevel(dataTextureC, u_sampler, prevPos, 0.0).rgb;
    
    // Add source (mouse position)
    let mousePos = u.zoom_config.yz;
    let dist = length(uv - mousePos);
    let source = smoothstep(0.1, 0.0, dist) * u.zoom_config.w;
    density += vec3<f32>(source * 0.1, source * 0.05, source * 0.2);
    
    // Fade
    density *= 0.995;
    
    textureStore(writeTexture, gid.xy, vec4<f32>(density, 1.0));
}

// Helper: Curl noise for turbulence
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let eps = 0.01;
    let n1 = noise(p + vec2<f32>(eps, 0.0));
    let n2 = noise(p - vec2<f32>(eps, 0.0));
    let n3 = noise(p + vec2<f32>(0.0, eps));
    let n4 = noise(p - vec2<f32>(0.0, eps));
    
    return vec2<f32>(n4 - n3, n1 - n2) / (2.0 * eps);
}
```

---

### Technique 7: Falling Sand / Powder

Cellular automata simulation of granular materials.

```wgsl
@compute @workgroup_size(16, 16, 1)
fn sandSimulation(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    let pixel = 1.0 / u.config.zw;
    
    // Read current cell
    let self = textureLoad(dataTextureA, gid.xy, 0).r;
    
    // Read neighbors
    let below = textureLoad(dataTextureA, gid.xy + vec2<i32>(0, -1), 0).r;
    let belowLeft = textureLoad(dataTextureA, gid.xy + vec2<i32>(-1, -1), 0).r;
    let belowRight = textureLoad(dataTextureA, gid.xy + vec2<i32>(1, -1), 0).r;
    
    var newState = self;
    
    if (self > 0.5) {
        // Sand particle - try to fall
        if (below < 0.5) {
            // Fall straight down
            newState = 0.0;
        } else if (belowLeft < 0.5) {
            // Slide left
            newState = 0.0;
        } else if (belowRight < 0.5) {
            // Slide right
            newState = 0.0;
        }
    } else {
        // Empty - check if sand falls into here
        let above = textureLoad(dataTextureA, gid.xy + vec2<i32>(0, 1), 0).r;
        let aboveLeft = textureLoad(dataTextureA, gid.xy + vec2<i32>(-1, 1), 0).r;
        let aboveRight = textureLoad(dataTextureA, gid.xy + vec2<i32>(1, 1), 0).r;
        
        if (above > 0.5) {
            newState = above;
        } else if (aboveLeft > 0.5 && textureLoad(dataTextureA, gid.xy + vec2<i32>(0, 1), 0).r > 0.5) {
            newState = aboveLeft;
        } else if (aboveRight > 0.5 && textureLoad(dataTextureA, gid.xy + vec2<i32>(0, 1), 0).r > 0.5) {
            newState = aboveRight;
        }
    }
    
    // Add new sand at mouse position
    let mousePos = u.zoom_config.yz;
    let mouseDist = length(uv - mousePos);
    if (mouseDist < 0.02 && u.config.y > 0.5) {
        newState = 1.0;
    }
    
    // Color based on state
    let color = select(vec3<f32>(0.0), vec3<f32>(0.9, 0.7, 0.4), newState > 0.5);
    
    textureStore(writeTexture, gid.xy, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, gid.xy, vec4<f32>(newState, 0.0, 0.0, 1.0));
}
```

---

### Technique 8: Slime Mold (Physarum)

Agent-based simulation with trail following.

```wgsl
// Simplified version - full version would use storage buffers

fn slimeMold(uv: vec2<f32>, time: f32) -> vec3<f32> {
    // Trail map stored in dataTextureA
    let trail = textureLoad(dataTextureA, vec2<i32>(uv * u.config.zw), 0).r;
    
    // Diffuse and decay trails
    let pixel = 1.0 / u.config.zw;
    var sum = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            sum += textureLoad(dataTextureA, vec2<i32>(uv * u.config.zw) + vec2<i32>(x, y), 0).r;
        }
    }
    let diffused = sum / 9.0;
    let decayed = diffused * 0.95;
    
    // Deposit new trails at agent positions
    // (Agents would be simulated separately)
    let mousePos = u.zoom_config.yz;
    let dist = length(uv - mousePos);
    let deposit = smoothstep(0.05, 0.0, dist) * 0.1;
    
    let newTrail = min(decayed + deposit, 1.0);
    
    // Color: cyan trails
    let color = vec3<f32>(0.0, newTrail, newTrail * 0.8);
    
    return color;
}
```

---

### Technique 9: Heat Haze / Convection

Temperature field driving refraction.

```wgsl
fn heatHaze(uv: vec2<f32>, time: f32) -> vec2<f32> {
    // Temperature field in dataTextureA
    let temp = textureLoad(dataTextureA, vec2<i32>(uv * u.config.zw), 0).r;
    
    // Temperature gradient drives displacement
    let pixel = 1.0 / u.config.zw;
    let tempRight = textureLoad(dataTextureA, vec2<i32>((uv + vec2<f32>(pixel.x, 0.0)) * u.config.zw), 0).r;
    let tempUp = textureLoad(dataTextureA, vec2<i32>((uv + vec2<f32>(0.0, pixel.y)) * u.config.zw), 0).r;
    
    let grad = vec2<f32>(tempRight - temp, tempUp - temp);
    
    // Hot air rises (negative y direction)
    let displacement = vec2<f32>(grad.x, -temp * 0.5) * 0.02;
    
    // Add noise for shimmer
    let shimmer = noise(uv * 20.0 + time * 2.0) * temp * 0.01;
    
    return uv + displacement + shimmer;
}

// Temperature simulation (separate pass)
fn updateTemperature(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    
    // Diffuse temperature
    let pixel = 1.0 / u.config.zw;
    var sum = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            sum += textureLoad(dataTextureA, gid.xy + vec2<i32>(x, y), 0).r;
        }
    }
    let diffused = sum / 9.0;
    
    // Cool over time
    let cooled = diffused * 0.98;
    
    // Heat source at bottom
    let heatSource = smoothstep(0.1, 0.0, uv.y) * 0.1;
    
    // Mouse heat
    let mouseHeat = smoothstep(0.1, 0.0, length(uv - u.zoom_config.yz)) * 0.2;
    
    let newTemp = min(cooled + heatSource + mouseHeat, 1.0);
    
    textureStore(dataTextureA, gid.xy, vec4<f32>(newTemp, 0.0, 0.0, 1.0));
}
```

---

### Technique 10: Fake Volumetrics

Approximate volumetric lighting cheaply.

```wgsl
fn fakeVolumetrics(uv: vec2<f32>, lightPos: vec2<f32>) -> vec3<f32> {
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    // Radial blur toward light source
    let toLight = lightPos - uv;
    let distToLight = length(toLight);
    let dirToLight = normalize(toLight);
    
    var volumetric = vec3<f32>(0.0);
    let samples = 16;
    
    for (var i = 0; i < samples; i++) {
        let t = f32(i) / f32(samples);
        let samplePos = uv + dirToLight * t * distToLight * 0.5;
        
        // Sample scene color
        let sampleColor = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).rgb;
        let luma = dot(sampleColor, vec3<f32>(0.299, 0.587, 0.114));
        
        // Occlusion check (simplified)
        let occlusion = luma;
        
        // Accumulate
        volumetric += vec3<f32>(1.0) * (1.0 - occlusion) * (1.0 - t);
    }
    volumetric /= f32(samples);
    
    // Density factor
    let density = 0.3;
    volumetric *= density;
    
    // Tint
    let sunColor = vec3<f32>(1.0, 0.9, 0.7);
    volumetric *= sunColor;
    
    // Add to base
    return baseColor + volumetric;
}
```

---

## Implementation Checklist

### For Temporal Effects:
- [ ] Previous frame available (dataTextureC or ping-pong)
- [ ] Frame differencing implemented
- [ ] Motion vectors calculated
- [ ] Feedback/decay rate tuned
- [ ] Temporal artifacts minimized

### For Simulations:
- [ ] Multi-pass architecture set up
- [ ] Data textures configured
- [ ] Boundary conditions handled
- [ ] Parameters are tunable
- [ ] Performance acceptable (target 30fps+)

---

## Category Assignments

| Technique | Category | Multi-Pass? |
|-----------|----------|-------------|
| Motion Trail | image | Yes |
| Datamosh | glitch | Yes |
| Velocity Bloom | lighting-effects | No |
| Echo Chamber | image | Yes |
| Fluid Sim | simulation | Yes |
| Falling Sand | simulation | Yes |
| Slime Mold | simulation | Yes |
| Heat Haze | distortion | Yes |
| Fake Volumetrics | lighting-effects | No |

---

## Performance Tips

1. **Use lower resolution for simulation** - Run physics at 0.5x or 0.25x resolution
2. **Limit iterations** - Fixed small loop counts are faster
3. **Branchless where possible** - Use mix/select instead of if
4. **Reuse calculations** - Don't compute the same value twice
5. **Texture lookup vs compute** - Sometimes sampling a precomputed texture is faster
