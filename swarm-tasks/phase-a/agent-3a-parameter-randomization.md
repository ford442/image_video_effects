# Agent 3A: Parameter Randomization Engineer
## Task Specification - Phase A, Agent 3

**Role:** Randomization Safety Specialist  
**Priority:** HIGH  
**Target:** Validate/fix all Phase A shaders for randomization safety  
**Estimated Duration:** 2-3 days

---

## Mission

Ensure ALL shaders in Phase A work correctly with the "Randomize" button. The Randomize button sets `zoom_params.x/y/z/w` to random values between 0.0 and 1.0 simultaneously.

---

## The Randomization Problem

### How Randomize Works
```typescript
// From the application code
function randomizeParams() {
  return {
    x: Math.random(), // 0.0 to 1.0
    y: Math.random(), // 0.0 to 1.0
    z: Math.random(), // 0.0 to 1.0
    w: Math.random()  // 0.0 to 1.0
  };
}
// These values go directly to u.zoom_params
```

### Common Failures

| Failure | Cause | Example |
|---------|-------|---------|
| Black screen | Division by zero | `1.0 / param` when param = 0 |
| White screen | log(0) or pow(0, 0) | `log(param)` when param = 0 |
| Glitch/NaN | sqrt(negative) | `sqrt(param - 0.5)` when param < 0.5 |
| Invisible | Alpha = 0 | `alpha = param - 0.5` when param < 0.5 |
| Too intense | Unbounded growth | `scale = 1.0 + param * 100.0` |

---

## Validation Process

### Step 1: Identify Unsafe Patterns

Search for these dangerous patterns in each shader:

```wgsl
// DANGER: Division by parameter
let scale = 1.0 / u.zoom_params.x;
let freq = 10.0 / param;

// DANGER: Log of parameter
let val = log(u.zoom_params.y);
let val = log2(param);

// DANGER: Pow with variable exponent and zero base
let val = pow(someValue, u.zoom_params.z); // if someValue can be 0

// DANGER: Square root of potentially negative
let val = sqrt(param - 0.5);
let val = length(vec2<f32>(param - 1.0, 0.0));

// DANGER: Asin/Acos outside [-1, 1]
let angle = asin(param * 2.0 - 1.0); // Actually safe, but check

// DANGER: Zero alpha
let alpha = param - 0.5; // Negative when param < 0.5

// DANGER: Infinite loops (rare but possible)
for (var i = 0.0; i < param * 100.0; i++) { } // 0 iterations when param=0, that's ok
```

### Step 2: Apply Safe Patterns

Replace unsafe patterns with safe equivalents:

#### Division Safety
```wgsl
// UNSAFE:
let scale = 1.0 / u.zoom_params.x;

// SAFE:
let scale = 1.0 / (u.zoom_params.x + 0.001);
// OR with minimum:
let denom = max(u.zoom_params.x, 0.001);
let scale = 1.0 / denom;
```

#### Log Safety
```wgsl
// UNSAFE:
let val = log(u.zoom_params.y);

// SAFE:
let val = log(u.zoom_params.y + 0.001);
// OR:
let val = log(max(u.zoom_params.y, 0.001));
```

#### Pow Safety
```wgsl
// UNSAFE:
let val = pow(base, u.zoom_params.z);

// SAFE (ensure positive base):
let val = pow(abs(base) + 0.001, u.zoom_params.z);
// OR limit exponent when base can be 0:
let safeExp = max(u.zoom_params.z, 0.001);
let val = select(0.0, pow(base, safeExp), base > 0.0);
```

#### Sqrt Safety
```wgsl
// UNSAFE:
let dist = sqrt(param - 0.5);

// SAFE:
let dist = sqrt(max(param - 0.5, 0.0));
```

#### Alpha Safety
```wgsl
// UNSAFE:
let alpha = param - 0.5; // Goes negative!

// SAFE:
let alpha = max(param - 0.5, 0.1); // Minimum 0.1
// OR use smoothstep:
let alpha = smoothstep(0.0, 1.0, param); // Always 0-1
// OR use mix:
let alpha = mix(0.3, 1.0, param); // Always 0.3-1.0
```

#### Parameter Remapping
```wgsl
// For parameters that need specific ranges
let freq = mix(0.5, 10.0, u.zoom_params.x);     // Safe: 0.5-10, never 0
let count = f32(i32(u.zoom_params.y * 8.0) + 2); // Safe: 2-10 integers
let angle = u.zoom_params.z * 6.28318;           // Safe: 0-2π
let intensity = mix(0.1, 2.0, u.zoom_params.w);  // Safe: minimum 0.1
```

### Step 3: Test Critical Values

For each shader, verify it works at these specific values:

```wgsl
// Test Case 1: All zeros
zoom_params = vec4<f32>(0.0, 0.0, 0.0, 0.0);
// Expected: Should still render something visible

// Test Case 2: All ones
zoom_params = vec4<f32>(1.0, 1.0, 1.0, 1.0);
// Expected: Should render, not blow out to white

// Test Case 3: Random mix
zoom_params = vec4<f32>(0.23, 0.87, 0.11, 0.65);
// Expected: Should be valid intermediate state

// Test Case 4: Edge cases
zoom_params = vec4<f32>(0.001, 0.001, 0.999, 0.999);
// Expected: Should handle near-zero and near-one safely
```

---

## Shader Audit List

### Phase A Shaders to Validate

#### Tiny Shaders (9)
- [ ] texture
- [ ] gen_orb
- [ ] gen_grokcf_interference
- [ ] gen_grid
- [ ] gen_grokcf_voronoi
- [ ] gen_grok41_plasma
- [ ] galaxy
- [ ] gen_trails
- [ ] gen_grok41_mandelbrot

#### Small Shaders (52) - Sample Key Ones
- [ ] imageVideo
- [ ] gen_julia_set
- [ ] quantized-ripples
- [ ] scanline-wave
- [ ] luma-flow-field
- [ ] phantom-lag
- [ ] frosty-window
- [ ] gen_wave_equation
- [ ] parallax-shift
- [ ] rgb-glitch-trail
- [ ] ion-stream
- [ ] radial-blur
- [ ] pixel-sort-glitch
- [ ] chromatic-shockwave
- [ ] selective-color
- [ ] liquid-jelly
- [ ] anamorphic-flare
- [ ] kaleidoscope
- [ ] pixel-repel
- [ ] lighthouse-reveal
- [ ] temporal-echo
- [ ] liquid
- [ ] liquid-rainbow
- [ ] vhs-tracking
- [ ] julia-warp

#### New Hybrid Shaders (10 from Agent 2A)
- [ ] hybrid-noise-kaleidoscope
- [ ] hybrid-sdf-plasma
- [ ] hybrid-chromatic-liquid
- [ ] hybrid-cyber-organic
- [ ] hybrid-voronoi-glass
- [ ] hybrid-fractal-feedback
- [ ] hybrid-magnetic-field
- [ ] hybrid-particle-fluid
- [ ] hybrid-reaction-diffusion-glass
- [ ] hybrid-spectral-sorting

---

## Common Safe Parameter Patterns

### Pattern: Normalized Intensity
```wgsl
let intensity = u.zoom_params.x; // 0.0 to 1.0
// Usage: Multiply base effect
let effect = baseEffect * (0.1 + intensity * 1.9); // 0.1x to 2.0x
```

### Pattern: Blend Factor
```wgsl
let blend = u.zoom_params.y; // 0.0 to 1.0
// Usage: Mix between two states
let result = mix(stateA, stateB, blend);
```

### Pattern: Frequency Scale
```wgsl
let freq = mix(0.5, 10.0, u.zoom_params.z); // Never 0
// Usage: Scale sampling frequency
let sampleUV = uv * freq;
```

### Pattern: Integer Count
```wgsl
let count = i32(u.zoom_params.w * 10.0) + 1; // 1 to 11
// Usage: Loop iterations
for (var i = 0; i < count; i++) { }
```

### Pattern: Angle
```wgsl
let angle = u.zoom_params.x * 6.28318; // 0 to 2π
// Usage: Rotation
let rotUV = rot2(angle) * uv;
```

### Pattern: Probability
```wgsl
let probability = u.zoom_params.y; // 0.0 to 1.0
// Usage: Threshold
if (randomValue < probability) { }
```

---

## Parameter Documentation Template

For each shader, document the parameter mapping:

```markdown
### Shader: {name}

| Param | Name | Range | Safe Mapping | Description |
|-------|------|-------|--------------|-------------|
| x | Intensity | 0.0-1.0 | `mix(0.1, 2.0, x)` | Effect strength |
| y | Frequency | 0.0-1.0 | `mix(0.5, 5.0, y)` | Pattern frequency |
| z | Blend | 0.0-1.0 | `z` (direct) | Mix factor |
| w | Speed | 0.0-1.0 | `mix(0.1, 3.0, w)` | Animation speed |

Issues Found:
- [ ] Division by zero at x=0 → Fixed by adding epsilon
- [ ] log(0) at y=0 → Fixed by using max(y, 0.001)
```

---

## Output Deliverables

1. **Validation Report** (`swarm-outputs/randomization-report.md`):
   - List of all shaders checked
   - Issues found per shader
   - Fixes applied
   - Test results for critical values

2. **Fixed Shader Files**:
   - Updated WGSL files with safe parameter handling
   - Comments marking changed lines

3. **Parameter Safety Guide**:
   - Common patterns to avoid
   - Safe replacement patterns
   - Testing methodology

---

## Success Criteria

- All 61+ Phase A shaders pass randomization tests
- No shader produces black screen at any parameter combination
- No shader crashes or produces NaN
- All parameters have safe mappings documented
- Report generated with before/after comparison
