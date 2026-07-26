# Swarm Brief: gen_grokcf_interference

**Role:** Algorithmist
**Name:** Cylindrical Drum Modes
**Category:** generative
**Description:** Vibrating circular membrane Bessel function modal synthesis: u_{mn} = J_m(α_{mn}·r/R)·cos(mφ)·cos(ω_{mn}·t). GPU polynomial Bessel J₀–J₃ (Abramowitz & Stegun). Audio bands activate mode families (bass→radial, mids→azimuthal, treble→higher-order). Chladni node-line colouring.
**Current lines:** 206
**Target lines:** 256–296 (expand by +50 to +90)

## Role Instructions

You are the Algorithmist. This Bessel drum-mode shader has a mislabeled slider and dead mouse code - make the labels honest, then give the membrane a real strike:
- MAKE 'COLOUR MODE' HONEST (priority 1): zoom_params.y is only consumed by the applyGenerativePrimaryControls boilerplate (brightness pulse) - the slider does nothing color-related. Evict the boilerplate and wire y to a real hue rotation of the base color before the Chladni mix. Keep the JSON id/name/default EXACTLY (saved-preset contract). Also remove the x-param double duty (modeScale AND boilerplate intensity fighting on one slider) - x drives modeScale only.
- Remove the dead mouse code: `rc` and `phic` are computed from zoom_config.yz and never used (stale 'mouse shifts drum centre' comment). Either delete them or - better - make the mouse genuinely offset the drum center via the (r, phi) polar mapping.
- Membrane strikes: loop ripples[] (guard `min(u32(u.config.y), 50u)`) injecting a decaying impulse into u_total at each click point (a real drum hit); weight each drum mode by its matching FFT bin `plasmaBuffer[1 + (mode % 8)]` for truer cymatics.
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the Abramowitz & Stegun J0/J1 polynomial coefficients and the tabulated Bessel zeros (2.4048, 5.5201, 3.8317, 7.0156, 5.1356, 6.3802) VERBATIM - they are the physical correctness of the modal model. dataTextureA stores SIM STATE (u_total, r, phi/2pi, blendAlpha) - never clamp/tonemap it.

## Required Output Format

- Return exactly one fenced WGSL block (` ```wgsl ` ... ` ``` `).
- No prose before or after the fence.
- Preserve the canonical 13-binding compute layout:
  - @binding(0) sampler, (1) readTexture, (2) writeTexture, (3) Uniforms, (4) readDepthTexture, (5) non_filtering_sampler, (6) writeDepthTexture, (7) dataTextureA, (8) dataTextureB, (9) dataTextureC, (10) extraBuffer (read_write), (11) comparison_sampler, (12) plasmaBuffer (read).
- Workgroup size must be `@workgroup_size(16, 16, 1)`.
- Write to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame.
- Use `textureSampleLevel(..., 0.0)` for sampler reads and `textureLoad` for storage reads.
- Do not use WGSL reserved keywords as identifiers (e.g. `target`). Do not add or renumber bindings. Binding 13 (historyTexture) is optional - only declare it if the shader already uses it.
- extraBuffer (if ever used): [0..4] reserved, [5..132] = engine FFT bins - persistent shader state goes in [133..255] ONLY.
- Engine uniform truth (verified src/renderer/UniformBuffer.ts): config = [time, rippleCount, resW, resH]; zoom_config = [time, mouseX, mouseY, mouseDown]. Guard ripple loops with `min(u32(u.config.y), 50u)`.

## JSON Parameters / Controls

```json
{
  "id": "gen-grokcf-interference",
  "name": "Cylindrical Drum Modes",
  "url": "shaders/gen_grokcf_interference.wgsl",
  "description": "Vibrating circular membrane Bessel function modal synthesis: u_{mn} = J_m(\u03b1_{mn}\u00b7r/R)\u00b7cos(m\u03c6)\u00b7cos(\u03c9_{mn}\u00b7t). GPU polynomial Bessel J\u2080\u2013J\u2083 (Abramowitz & Stegun). Audio bands activate mode families (bass\u2192radial, mids\u2192azimuthal, treble\u2192higher-order). Chladni node-line colouring.",
  "features": [
    "upgraded-rgba",
    "depth-aware",
    "audio-reactive",
    "procedural",
    "animated"
  ],
  "tags": [
    "procedural",
    "generative",
    "cymatics",
    "bessel",
    "drum",
    "audio-reactive",
    "chladni",
    "physics"
  ],
  "params": [
    {
      "id": "modeScale",
      "name": "Mode Scale",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Controls the overall strength of the generated effect."
    },
    {
      "id": "colorMode",
      "name": "Colour Mode",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Controls animation and temporal evolution speed."
    },
    {
      "id": "nodeSharpness",
      "name": "Node Sharpness",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Controls spatial scale, frequency, or detail contrast."
    },
    {
      "id": "modeCount",
      "name": "Mode Count",
      "default": 0.6,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Controls mouse-driven or secondary variation influence."
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "Mode Scale",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "Colour Mode",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "Node Sharpness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Mode Count",
      "default": 0.6,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ],
  "updated": true
}
```

## Current WGSL Code

```wgsl
// ═══════════════════════════════════════════════════════════════════════════════
//  Cylindrical Drum Modes — Bessel Function Modal Synthesis
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, procedural, animated
//  Complexity: High
//  Scientific: Vibrating circular membrane modes u_{mn}(r,φ,t) =
//              J_m(α_{mn}·r/R)·cos(m·φ+φ₀)·cos(ω_{mn}·t),
//              polynomial approximation to Bessel J₀…J₃ on GPU,
//              audio bands activate different (m,n) mode families:
//              bass→(0,1)(0,2), mids→(1,1)(2,1), treble→(1,2)(3,1),
//              Chladni node-line colour coding (zero-crossings → white),
//              multi-mode interference creates quasi-chaotic patterns
//  Upgraded: Phase B
// ═══════════════════════════════════════════════════════════════════════════════

@group(0) @binding(0)  var u_sampler: sampler;
@group(0) @binding(1)  var readTexture: texture_2d<f32>;
@group(0) @binding(2)  var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3)  var<uniform> u: Uniforms;
@group(0) @binding(4)  var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5)  var non_filtering_sampler: sampler;
@group(0) @binding(6)  var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7)  var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8)  var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9)  var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,  // x=ModeScale, y=ColorMode, z=NodeSharpness, w=ModeCount
    ripples:     array<vec4<f32>, 50>,
}
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(acesToneMap(controlled * 1.1), color.a);
}


// ─── Polynomial Bessel approximations (Abramowitz & Stegun 9.4) ───
// J₀(x)  — accurate for x ∈ [0, 8] via two-range polynomial
fn J0(x: f32) -> f32 {
    let ax = abs(x);
    if (ax < 8.0) {
        let y = x * x;
        let p1 = 57568490574.0 - y*(13362590354.0 - y*(651619640.7 - y*(11214424.18 - y*(77392.33017 - y*184.9052456))));
        let q1 = 57568490411.0 + y*(1029532985.0 + y*(9494680.718 + y*(59272.64853 + y*(267.8532712 + y))));
        return p1 / q1;
    }
    let z  = 8.0 / ax;
    let y  = z * z;
    let xx = ax - 0.785398164;
    let p1 = 1.0 + y*(-0.1098628627e-2 + y*(0.2734510407e-4 + y*(-0.2073370639e-5 + y*0.2093887211e-6)));
    let q1 = -0.1562499995e-1 + y*(0.1430488765e-3 + y*(-0.6911147651e-5 + y*(0.7621095161e-6 - y*0.934945152e-7)));
    return sqrt(0.636619772 / ax) * (cos(xx) * p1 - z * sin(xx) * q1);
}

fn J1(x: f32) -> f32 {
    let ax = abs(x);
    if (ax < 8.0) {
        let y = x * x;
        let p1 = x*(72362614232.0 - y*(7895059235.0 - y*(242396853.1 - y*(2972611.439 - y*(15704.48260 - y*30.16036606)))));
        let q1 = 144725228442.0 + y*(2300535178.0 + y*(18583304.74 + y*(99447.43394 + y*(376.9991397 + y))));
        return p1 / q1;
    }
    let z  = 8.0 / ax;
    let y  = z * z;
    let xx = ax - 2.356194491;
    let p1 = 1.0 + y*(0.183105e-2 + y*(-0.3516396496e-4 + y*(0.2457520174e-5 - y*0.240337019e-6)));
    let q1 = 0.04687499995 + y*(-0.2002690873e-3 + y*(0.8449199096e-5 + y*(-0.88228987e-6 + y*0.105787412e-6)));
    let ans = sqrt(0.636619772 / ax) * (cos(xx) * p1 - z * sin(xx) * q1);
    return select(ans, -ans, x < 0.0);
}

// J₂, J₃ via recurrence: J_{n+1} = (2n/x)·J_n − J_{n-1}
fn J2(x: f32) -> f32 {
    if (abs(x) < 0.001) { return 0.0; }
    return (2.0 / x) * J1(x) - J0(x);
}
fn J3(x: f32) -> f32 {
    if (abs(x) < 0.001) { return 0.0; }
    return (4.0 / x) * J2(x) - J1(x);
}

// Drum mode u_{mn}: J_m(alpha_mn * r/R) * cos(m*phi + phi0) * cos(omega_mn * t)
// alpha_mn = first/second zero of J_m (tabulated constants)
fn drumMode(r: f32, phi: f32, t: f32, m: i32, alpha_mn: f32, omega: f32, phi0: f32) -> f32 {
    let bessel = select(
        select(
            select(J3(alpha_mn * r), J2(alpha_mn * r), m == 2),
            J1(alpha_mn * r), m == 1
        ),
        J0(alpha_mn * r), m == 0
    );
    return bessel * cos(f32(m) * phi + phi0) * cos(omega * t);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv     = vec2<f32>(global_id.xy) / resolution;
    let time   = u.config.x;
    let coord  = vec2<i32>(global_id.xy);
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let modeScale   = mix(0.5, 2.5, u.zoom_params.x);
    let nodeSharp   = mix(2.0, 30.0, u.zoom_params.z);
    let modeCount   = floor(u.zoom_params.w * 6.0) + 2.0;

    // Polar coords centred on screen
    let p     = (uv - 0.5) * 2.0;
    let r     = length(p) * modeScale;
    let phi   = atan2(p.y, p.x);

    // Mouse offset shifts the drum centre
    let mouse = u.zoom_config.yz;
    let rc    = length((uv - mouse) * 2.0) * modeScale;
    let phic  = atan2((uv.y - mouse.y), (uv.x - mouse.x));

    // ─── Mode family activation by audio band ───
    // First zeros of J_m: J0→2.4048, 5.5201; J1→3.8317, 7.0156; J2→5.1356; J3→6.3802
    var u_total = 0.0;

    // Bass → (0,1) and (0,2) radially symmetric modes
    u_total += drumMode(r, phi, time, 0, 2.4048, 2.4048 * 0.5, 0.0) * (0.5 + bass * 0.5);
    if (modeCount >= 3.0) {
        u_total += drumMode(r, phi, time, 0, 5.5201, 5.5201 * 0.5, 0.0) * (0.3 + bass * 0.3);
    }

    // Mids → (1,1) and (2,1)
    u_total += drumMode(r, phi, time, 1, 3.8317, 3.8317 * 0.5, 0.7) * (0.4 + mids * 0.5);
    if (modeCount >= 4.0) {
        u_total += drumMode(r, phi, time, 2, 5.1356, 5.1356 * 0.5, 1.2) * (0.3 + mids * 0.4);
    }

    // Treble → (1,2) and (3,1)
    if (modeCount >= 5.0) {
        u_total += drumMode(r, phi, time, 1, 7.0156, 7.0156 * 0.5, 0.3) * (0.2 + treble * 0.5);
    }
    if (modeCount >= 6.0) {
        u_total += drumMode(r, phi, time, 3, 6.3802, 6.3802 * 0.5, 2.1) * (0.15 + treble * 0.4);
    }

    // ─── Boundary: circular membrane fixed at r = R ───
    let R     = 0.9;
    let inside = smoothstep(R + 0.03, R, r / modeScale);
    u_total *= inside;

    // ─── Chladni node-line colouring ───
    // Nodes are zero-crossings: glow proportional to |u_total|
    let nodeEdge  = abs(u_total);
    let nodeGlow  = smoothstep(0.0, 0.5 / nodeSharp, nodeEdge) *
                    smoothstep(1.5 / nodeSharp, 0.5 / nodeSharp, nodeEdge);

    // Displacement → hue
    let hue    = fract(u_total * 0.15 + time * 0.04 + bass * 0.08);
    let sat    = 0.85;
    let val    = clamp(abs(u_total) * 1.5, 0.0, 1.0) * inside;
    // HSV → RGB
    let hi = floor(hue * 6.0);
    let f  = hue * 6.0 - hi;
    let p_ = val * (1.0 - sat);
    let q_ = val * (1.0 - f * sat);
    let tv = val * (1.0 - (1.0 - f) * sat);
    let m  = i32(hi) % 6;
    var baseColor: vec3<f32>;
    if (m == 0) { baseColor = vec3<f32>(val, tv, p_); }
    else if (m == 1) { baseColor = vec3<f32>(q_, val, p_); }
    else if (m == 2) { baseColor = vec3<f32>(p_, val, tv); }
    else if (m == 3) { baseColor = vec3<f32>(p_, q_, val); }
    else if (m == 4) { baseColor = vec3<f32>(tv, p_, val); }
    else             { baseColor = vec3<f32>(val, p_, q_); }

    // Nodes → white/gold Chladni lines
    let chladniColor = mix(baseColor, vec3<f32>(1.0, 0.9, 0.7), nodeGlow * 0.7);

    // Blend with image input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let blendAlpha = clamp(val * 0.85 + nodeGlow * 0.3 + bass * 0.05, 0.0, 1.0);
    let finalColor = mix(inputColor, chladniColor, blendAlpha);

    textureStore(writeTexture, coord, applyGenerativePrimaryControls(vec4<f32>(finalColor, 1.0)));
    textureStore(dataTextureA, coord, vec4<f32>(u_total, r, phi / 6.28318, blendAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));
}
```
