# Agent 1C: Spectral-Domain Architect
## Task Specification - Phase C, Agent 1

**Role:** Frequency-Domain Shader Architect
**Priority:** HIGH (unlocks a whole class of effects the library currently cannot express)
**Target:** Create 2 new mouse-responsive compute shaders that operate in the spectral domain
**Estimated Duration:** 4-5 days

---

## Mission

Bring **frequency-domain processing** to the shader library. Today every "frequency-like" effect is faked with FBM or domain warping — there is no true 2D Fourier analysis or oriented wavelet bank in `public/shaders/`. Phase C opens this door with a Cooley-Tukey 2D FFT (implemented as a ping-pong butterfly pass chain) and a Gabor wavelet kaleidoscope. Both are driven by the mouse and produce spectacularly psychedelic, non-linear imagery that cannot be produced from spatial-domain filters.

---

## Shader Concepts

### 1. `spectral-mirror` (5-pass: row-FFT, col-FFT, mouse-sculpt, col-IFFT, row-IFFT)

**Concept:** Transform the input image into the frequency domain, let the mouse sculpt its spectrum, then invert. Low-frequency pulls produce dreamy bokeh; high-frequency spikes produce ringing hallucinations.

**Complexity:** Very High
**Primary Techniques:**
- Radix-2 Cooley-Tukey butterfly (in-place, bit-reversed input)
- Complex-number packing in `rgba32float`
- Mouse paints in log-polar frequency space

**RGBA32FLOAT packing (introduced by this shader):**
```
dataTextureA.r = Re( F[u,v] )
dataTextureA.g = Im( F[u,v] )
dataTextureA.b = |F|  (cached for painting)
dataTextureA.a = arg(F) (cached for painting)
```

**Binding usage:**
- `readTexture` (1): source image (first pass only)
- `writeTexture` (2): final reconstructed RGB (last pass only)
- `dataTextureA` (7): spectrum storage (read/write across passes)
- `dataTextureB` (8): scratch for the second axis
- `dataTextureC` (9): feedback — previous frame's sculpted spectrum (for temporal smoothing)
- `extraBuffer` (10): bit-reversal permutation table, precomputed once

```wgsl
// Pass 3: mouse sculpts the spectrum in log-polar space
let centered = vec2<f32>(f32(global_id.x), f32(global_id.y)) - 0.5 * res;
let r = length(centered);
let theta = atan2(centered.y, centered.x);
let log_r = log(max(r, 1.0));

// Mouse position is mapped to (log_radius, angle)
let mouse_log_r = u.zoom_params.x * log(0.5 * res.x);
let mouse_theta = (u.zoom_config.y - 0.5) * 6.2831853;
let d = length(vec2<f32>(log_r - mouse_log_r, angular_delta(theta, mouse_theta)));

// Gaussian bump centered on cursor in frequency space
let gain = 1.0 + u.zoom_params.y * u.zoom_config.w * exp(-d * d / (u.zoom_params.z * u.zoom_params.z));
let F = textureLoad(dataTextureA, vec2<i32>(global_id.xy), 0);
let new_mag = length(F.xy) * gain;
let phase  = atan2(F.y, F.x) + u.zoom_params.w * u.zoom_config.w * sin(theta * 5.0);
textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(new_mag * cos(phase), new_mag * sin(phase), new_mag, phase));
```

**Butterfly skeleton (passes 1, 2, 4, 5):**
```wgsl
// Radix-2 DIT butterfly, stage `s` of log2(N) stages
let pair  = global_id.x ^ (1u << s);
let butterfly_lo = min(global_id.x, pair);
let twiddle_k = (butterfly_lo & ((1u << s) - 1u));
let angle = -6.2831853 * f32(twiddle_k) / f32(2u << s);
let w = vec2<f32>(cos(angle), sin(angle));
// Read both halves, compute new_lo = a + w*b, new_hi = a - w*b
```

**Visual:** The image floats behind a translucent spectrum. Dragging outward from the center pulls low frequencies into painterly blurs; orbiting at mid-radius stretches the spectrum into rainbow auroras; clicking at high radius introduces ringing halos that wrap the image like stained glass.

**Params:**
- x: Mouse-in-frequency radius (0 = DC / blur, 1 = Nyquist / sharpen)
- y: Magnitude gain at mouse bump (0-1 → ×1 to ×8)
- z: Bump width σ (narrow = single-tone artifact, wide = global shift)
- w: Phase-twist amount (0 = pure mag sculpt, 1 = full phase psychedelia)

**RGB-from-RGBA strategy:** Alpha of input is multiplied into the DC bin before FFT, so transparent regions become *low-frequency* energy that the inverse transform spreads into the final RGB.

**Performance notes:**
- At 1024×1024, one butterfly stage is 1024² work → 5 passes × log₂(1024)=10 stages ≈ 50 dispatches.
- Prefer 512×512 working resolution; upsample on the final pass.
- Workgroup size `256×1×1` for butterfly passes, `16×16×1` for the sculpt pass.

---

### 2. `gabor-wavelet-kaleidoscope` (3-pass: bank-decompose, mouse-mix, synthesize)

**Concept:** Decompose the image onto a bank of 12 oriented Gabor wavelets (4 scales × 3 orientations). The mouse chooses which orientation/scale to amplify; the synthesis recomposes them with psychedelic per-channel gain. Like running the image through a bank of tuning forks and letting the cursor strike one.

**Complexity:** High
**Primary Techniques:**
- Oriented Gabor filter: `g(x,y) = exp(-(x² + γ²y²)/(2σ²)) · cos(2π x' / λ)`
- Multi-scale decomposition stored across `.r .g .b .a` of a single rgba32float pixel
- Mouse cursor = "hand on the tuning fork"

**RGBA32FLOAT packing:**
```
dataTextureA.rgba = responses at scales (σ, 2σ, 4σ, 8σ) at orientation 0°
dataTextureB.rgba = responses at same scales at orientation 60°
dataTextureC (read feedback) carries orientation 120° from previous frame
```
(No need for a fourth binding — the 3rd orientation is recomputed fresh every frame from `readTexture`.)

**Binding usage:**
- `readTexture` (1): source image
- `writeTexture` (2): synthesized output
- `dataTextureA` (7): orientation 0 bank
- `dataTextureB` (8): orientation 60 bank
- `dataTextureC` (9): orientation 120 bank (previous frame)

```wgsl
// Pass 1: compute Gabor response at (scale, orientation) for every pixel
fn gabor(p: vec2<f32>, sigma: f32, theta: f32, lambda: f32) -> f32 {
    let c = cos(theta); let s = sin(theta);
    let x_p =  c * p.x + s * p.y;
    let y_p = -s * p.x + c * p.y;
    let env = exp(-(x_p*x_p + 2.0*y_p*y_p) / (2.0 * sigma * sigma));
    return env * cos(6.2831853 * x_p / lambda);
}

// Sum of gabor · luma over a 7x7 neighborhood = response[scale]
var response: vec4<f32>;
for (var k = 0u; k < 4u; k++) {
    let sigma = 1.5 * pow(2.0, f32(k));
    var acc = 0.0;
    for (var dy = -3; dy <= 3; dy++) {
      for (var dx = -3; dx <= 3; dx++) {
        let sample = textureLoad(readTexture, vec2<i32>(global_id.xy) + vec2<i32>(dx,dy), 0);
        let luma = dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
        acc += gabor(vec2<f32>(f32(dx), f32(dy)), sigma, 0.0, sigma * 2.0) * luma;
      }
    }
    response[k] = acc;
}
textureStore(dataTextureA, vec2<i32>(global_id.xy), response);
```

```wgsl
// Pass 3: synthesize — mouse controls orientation & scale gain
let mouse_theta = u.zoom_config.y * 3.14159;    // 0..π
let mouse_scale = u.zoom_config.z * 4.0;        // 0..4
let gain_o0 = gaussian(angular_delta(0.0,        mouse_theta), u.zoom_params.x);
let gain_o1 = gaussian(angular_delta(1.0471976,  mouse_theta), u.zoom_params.x);
let gain_o2 = gaussian(angular_delta(2.0943951,  mouse_theta), u.zoom_params.x);
let r0 = textureLoad(dataTextureA, pix, 0);
let r1 = textureLoad(dataTextureB, pix, 0);
let r2 = textureLoad(dataTextureC, pix, 0);
let scale_weights = gaussian4(mouse_scale, u.zoom_params.y); // vec4
let per_chan_boost = u.zoom_params.z * u.zoom_config.w;
let y = gain_o0 * dot(r0, scale_weights) + gain_o1 * dot(r1, scale_weights) + gain_o2 * dot(r2, scale_weights);
// Paint per-channel for psychedelic chromatic separation
let rgb = base + per_chan_boost * vec3<f32>(
    y * cos(mouse_theta),
    y * cos(mouse_theta + 2.094),
    y * cos(mouse_theta + 4.188)
);
```

**Visual:** The image appears to have hidden "grain directions" — rotating the mouse resonates with the edges that run at that angle and makes them blaze with color. Dragging radially picks the scale, so thin textures or coarse swirls light up. Click-and-drag creates stained-glass-like chromatic kaleidoscopes.

**Params:**
- x: Orientation tuning bandwidth (0 = razor-sharp resonance, 1 = all orientations)
- y: Scale tuning bandwidth
- z: Chromatic boost (0 = grayscale resonance, 1 = full RGB splitting)
- w: Bank blend vs. passthrough (0 = original image, 1 = pure wavelet)

**RGB-from-RGBA strategy:** Alpha from the input attenuates the wavelet response before synthesis; transparent source pixels contribute less to the Gabor sum, so the synthesis naturally masks them.

**Performance notes:**
- 7×7 kernel × 4 scales = 196 taps per pixel per orientation → heavy. Can be made separable (Gabor factors into x' and y' 1D kernels) in a v2.
- Workgroup `8×8×1`; ~25 ms at 1920×1080.

---

## Deliverables

| File | Lines | Notes |
|------|-------|-------|
| `public/shaders/spectral-mirror-pass1.wgsl` | ~60 | bit-reversed row FFT |
| `public/shaders/spectral-mirror-pass2.wgsl` | ~60 | column FFT |
| `public/shaders/spectral-mirror-pass3.wgsl` | ~50 | mouse sculpt in log-polar |
| `public/shaders/spectral-mirror-pass4.wgsl` | ~60 | column IFFT |
| `public/shaders/spectral-mirror-pass5.wgsl` | ~60 | row IFFT + image normalize |
| `shader_definitions/interactive-mouse/spectral-mirror.json` | ~80 | multi-pass chain |
| `public/shaders/gabor-wavelet-kaleidoscope-pass1.wgsl` | ~80 | orientation 0 bank |
| `public/shaders/gabor-wavelet-kaleidoscope-pass2.wgsl` | ~80 | orientation 60 bank |
| `public/shaders/gabor-wavelet-kaleidoscope-pass3.wgsl` | ~90 | mouse mix + synthesis |
| `shader_definitions/interactive-mouse/gabor-wavelet-kaleidoscope.json` | ~80 | chain + params |

---

## Validation Checklist

- [ ] FFT round-trip error (IFFT(FFT(I)) - I) < 1e-3 per channel without mouse input.
- [ ] Bit-reversal permutation precomputed in `extraBuffer` at init.
- [ ] Gabor bank sums to unity when all gains are 1 (energy-preserving).
- [ ] Both shaders appear in the shader-browser UI with 4 params each.
- [ ] `naga-scan-report.json` passes with zero new errors.
- [ ] Bindgroup contract intact (verify with `bindgroup_checker.py`).
