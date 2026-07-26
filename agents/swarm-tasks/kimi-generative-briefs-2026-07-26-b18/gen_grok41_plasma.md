# Swarm Brief: gen_grok41_plasma

**Role:** Visualist
**Name:** Spherical Harmonics Plasma
**Category:** generative
**Description:** Audio-reactive 3D gas giant using Y(l,m) spherical harmonics with HDR ACES tone mapping, Rayleigh limb scattering, mouse-driven light, and treble-triggered lightning tendrils.
**Current lines:** 220
**Target lines:** 270–310 (expand by +50 to +90)

## Role Instructions

You are the Visualist. This spherical-harmonics gas giant has a DEAD Hue Shift slider and a missing bounds guard - fix both, then push the harmonics spectral:
- FIX THE DEAD HUE SHIFT (priority 1): `gasGiantColor()` builds `shiftMat` from the Hue Shift slider but never applies it (dead matrix). Apply the rotation to the final color so the slider works. Also add the missing OOB bounds guard (`if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }`).
- Band-specific harmonics: weight the three harmonic bands from per-bin FFT - l1 (Y1x) follows bass bins (`plasmaBuffer[1..3]`), l2 follows mid bins (`plasmaBuffer[4..6]`), l3 follows treble bins (`plasmaBuffer[7..8]`) - so each spherical-harmonic family dances to its own frequency range.
- Storm cells: add a subtle Worley noise overlay on the gas-giant band structure for cellular storm texture (keep it under 20% mix so the harmonics stay dominant).
- Wire exactly 4 slider params via u.zoom_params.x/y/z/w using the EXISTING JSON params (same ids, names, defaults, min/max/step, and mapping order) — add them to updatedParams with index 0-3. These param ids/defaults are the saved-preset contract: do not rename or re-default them.
- Make each slider drive meaningful shader-specific constants in the WGSL. If the current mapping is generic boilerplate (e.g. a shared intensity/speed/contrast helper), rewire it so each slider visibly controls a real constant of THIS shader's algorithm.
- Preserve the shader's core algorithm and its soul — upgrade, don't rewrite.
- CAUTION: preserve the 10 `Y00..Y30` spherical-harmonic functions VERBATIM - the constants are exact normalization coefficients. The existing bass-turbulence and treble-lightning audio paths stay intact.

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
  "id": "gen-grok41-plasma",
  "name": "Spherical Harmonics Plasma",
  "url": "shaders/gen_grok41_plasma.wgsl",
  "description": "Audio-reactive 3D gas giant using Y(l,m) spherical harmonics with HDR ACES tone mapping, Rayleigh limb scattering, mouse-driven light, and treble-triggered lightning tendrils.",
  "features": [
    "mouse-driven",
    "depth-aware",
    "upgraded-rgba",
    "3d",
    "audio-reactive",
    "spherical-harmonics",
    "animated"
  ],
  "tags": [
    "procedural",
    "generative",
    "sphere",
    "atmosphere",
    "spherical-harmonics",
    "gas-giant",
    "audio-reactive",
    "vj"
  ],
  "params": [
    {
      "id": "param1",
      "name": "L1 Coefficient",
      "default": 0.55,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "param2",
      "name": "L2 Coefficient",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "param3",
      "name": "L3 Coefficient",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "param4",
      "name": "Hue Shift",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "updatedParams": [
    {
      "index": 0,
      "name": "L1 Coefficient",
      "default": 0.55,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 1,
      "name": "L2 Coefficient",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 2,
      "name": "L3 Coefficient",
      "default": 0.4,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "index": 3,
      "name": "Hue Shift",
      "default": 0,
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
// ═══════════════════════════════════════════════════════════════════
//  Spherical Harmonics Plasma v2 - Audio-reactive gas giant
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            spherical-harmonics, animated
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  Creative additions: lightning tendrils on treble, Rayleigh limb scattering
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rotateX(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

fn rotateY(p: vec3<f32>, angle: f32) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec3<f32>(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

fn Y00(theta: f32, phi: f32) -> f32 { return 0.2820947918; }
fn Y10(theta: f32, phi: f32) -> f32 { return 0.4886025119 * cos(theta); }
fn Y1p1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * cos(phi); }
fn Y1n1(theta: f32, phi: f32) -> f32 { return -0.4886025119 * sin(theta) * sin(phi); }
fn Y20(theta: f32, phi: f32) -> f32 { return 0.3153915653 * (3.0 * cos(theta) * cos(theta) - 1.0); }
fn Y2p1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * cos(phi); }
fn Y2n1(theta: f32, phi: f32) -> f32 { return -1.0219854764 * sin(theta) * cos(theta) * sin(phi); }
fn Y2p2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * cos(2.0 * phi); }
fn Y2n2(theta: f32, phi: f32) -> f32 { return 0.5462742153 * sin(theta) * sin(theta) * sin(2.0 * phi); }
fn Y30(theta: f32, phi: f32) -> f32 {
    let ct = cos(theta);
    return 0.3731763326 * (5.0 * ct * ct * ct - 3.0 * ct);
}

fn gasGiantColor(value: f32, time: f32, hueShift: f32) -> vec3<f32> {
    let v = value * 0.5 + 0.5;
    let color1 = vec3<f32>(0.8, 0.6, 0.4);
    let color2 = vec3<f32>(0.6, 0.4, 0.2);
    let color3 = vec3<f32>(0.9, 0.5, 0.2);
    let color4 = vec3<f32>(0.7, 0.3, 0.15);
    let color5 = vec3<f32>(0.85, 0.7, 0.5);

    var color: vec3<f32>;
    if (v < 0.2) { color = mix(color1, color2, v * 5.0); }
    else if (v < 0.4) { color = mix(color2, color3, (v - 0.2) * 5.0); }
    else if (v < 0.6) { color = mix(color3, color4, (v - 0.4) * 5.0); }
    else if (v < 0.8) { color = mix(color4, color5, (v - 0.6) * 5.0); }
    else { color = mix(color5, color1, (v - 0.8) * 5.0); }

    // Hue rotation by hueShift
    let shiftMat = mat3x3<f32>(
        vec3<f32>(cos(hueShift * 6.28), -sin(hueShift * 6.28), 0.0),
        vec3<f32>(sin(hueShift * 6.28),  cos(hueShift * 6.28), 0.0),
        vec3<f32>(0.0, 0.0, 1.0)
    );

    let variation = sin(v * 20.0 + time) * 0.1;
    return color + vec3<f32>(variation);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let timeRaw = u.config.x;
    let time = timeRaw * 0.15;
    let uv = (vec2<f32>(global_id.xy) - resolution * 0.5) / min(resolution.x, resolution.y);
    let coord = vec2<i32>(global_id.xy);

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse for view + light direction
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    let mouseInfluence = u.zoom_config.w;

    // Sphere setup
    let sphereRadius = 0.45;
    let sphereCenter = vec3<f32>(0.0, 0.0, 0.0);
    let ro = vec3<f32>(0.0, 0.0, 1.8);
    let rd = normalize(vec3<f32>(uv.x, uv.y, -1.2));

    let rotTime = time * 0.5;
    let ro_rotated = rotateY(rotateX(ro, sin(time * 0.2) * 0.1), rotTime);
    let viewRotY = mouse.x * 0.5 * mouseInfluence;
    let viewRotX = mouse.y * 0.3 * mouseInfluence;
    let ro_final = rotateY(rotateX(ro_rotated, viewRotX), viewRotY);
    let rd_final = rotateY(rotateX(rd, viewRotX), viewRotY);

    let oc = ro_final - sphereCenter;
    let a = dot(rd_final, rd_final);
    let b = 2.0 * dot(oc, rd_final);
    let c_ = dot(oc, oc) - sphereRadius * sphereRadius;
    let discriminant = b * b - 4.0 * a * c_;

    let uv_norm = vec2<f32>(global_id.xy) / resolution;
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv_norm, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv_norm, 0.0).r;

    var outputColor = inputColor.rgb;
    var depth = inputDepth;
    var alpha = inputColor.a;
    let opacity = 0.9;

    if (discriminant > 0.0) {
        let t = (-b - sqrt(discriminant)) / (2.0 * a);
        let hitPoint = ro_final + rd_final * t;
        let normal = normalize(hitPoint - sphereCenter);
        let theta = acos(clamp(normal.y, -1.0, 1.0));
        let phi = atan2(normal.z, normal.x);

        // Bass amplifies turbulence
        let coeffs = u.zoom_params;
        let l1 = coeffs.x * (1.0 + bass * 0.6);
        let l2 = coeffs.y * (1.0 + bass * 0.6);
        let l3 = coeffs.z * (1.0 + bass * 0.6);
        let hueShift = coeffs.w + mids * 0.25;

        var pattern = 0.0;
        pattern = pattern + Y00(theta, phi) * 0.4;
        pattern = pattern + Y10(theta, phi) * sin(time * 0.5 + phi * 2.0) * l1;
        pattern = pattern + Y1p1(theta, phi) * cos(time * 0.3) * l1 * 0.5;
        pattern = pattern + Y1n1(theta, phi) * sin(time * 0.4) * l1 * 0.5;
        pattern = pattern + Y20(theta, phi) * cos(time * 0.6) * l2;
        pattern = pattern + Y2p1(theta, phi) * sin(time * 0.45 + theta) * l2 * 0.6;
        pattern = pattern + Y2n1(theta, phi) * cos(time * 0.55) * l2 * 0.6;
        pattern = pattern + Y2p2(theta, phi) * sin(time * 0.35 + phi * 3.0) * l2 * 0.4;
        pattern = pattern + Y2n2(theta, phi) * cos(time * 0.25) * l2 * 0.4;
        pattern = pattern + Y30(theta, phi) * sin(time * 0.7 + phi) * l3 * 0.5;

        let turbulence = sin(theta * 15.0 + time) * sin(phi * 12.0 - time * 0.5) * 0.05;
        pattern = pattern + turbulence * (l1 + l2 + l3) * 0.3 * (1.0 + bass * 0.8);

        // Mouse-controlled light direction (replaces fixed (0.8, 0.3, 1.0))
        let mouseLight = vec3<f32>(mouse.x, mouse.y, 0.6);
        let staticLight = vec3<f32>(0.8, 0.3, 1.0);
        let lightDir = normalize(mix(staticLight, mouseLight, mouseInfluence));
        let diff = max(dot(normal, lightDir), 0.0);
        let ambient = 0.25;
        let viewDir = -rd_final;
        let halfDir = normalize(lightDir + viewDir);
        let spec = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.3;
        let limbT = 1.0 - abs(dot(normal, viewDir));
        let rim = pow(limbT, 3.0) * 0.4;

        let baseColor = gasGiantColor(pattern, time, hueShift);
        // HDR accumulation (boost before tone map)
        var litColor = baseColor * (diff * 1.1 + ambient) * 1.4 + vec3<f32>(spec) * 1.5;

        // ─── Creative: Rayleigh-style blue limb scattering ───
        let rayleigh = pow(limbT, 2.5);
        let rayleighColor = vec3<f32>(0.35, 0.55, 1.0) * rayleigh * 0.9;
        litColor = litColor + rayleighColor;

        // Atmosphere rim + audio sparkle
        let atmosphereColor = vec3<f32>(0.6, 0.8, 1.0);
        litColor = litColor + atmosphereColor * rim;

        // ─── Creative: Lightning tendrils on treble ───
        let lightningSeed = hash21(vec2<f32>(floor(theta * 40.0), floor(phi * 40.0 + timeRaw * 30.0)));
        let lightningRand = hash21(vec2<f32>(floor(theta * 12.0), floor(phi * 12.0 + timeRaw * 8.0)));
        let lightningMask = step(0.985 - treble * 0.04, lightningSeed) * smoothstep(0.0, 0.6, limbT);
        let arcShape = pow(lightningRand, 8.0);
        litColor = litColor + vec3<f32>(0.7, 0.85, 1.0) * lightningMask * arcShape * (treble * 4.0 + 0.5);

        // Tone map
        let tonedColor = acesToneMapping(litColor);

        let rimAlpha = pow(limbT, 2.0);
        let hitAlpha = mix(0.9, 1.0, rimAlpha * 0.5);

        outputColor = mix(inputColor.rgb, tonedColor, hitAlpha * opacity);
        alpha = max(inputColor.a, hitAlpha * opacity);

        let clipZ = hitPoint.z;
        let generatedDepth = (clipZ + sphereRadius) / (sphereRadius * 2.0 + 1.8);
        depth = mix(inputDepth, generatedDepth, hitAlpha * opacity);
    }

    textureStore(writeTexture, coord, vec4<f32>(outputColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```
