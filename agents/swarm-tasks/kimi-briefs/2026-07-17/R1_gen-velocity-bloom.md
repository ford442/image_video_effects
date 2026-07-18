# KIMI SWARM TASK — REPAIR — gen-velocity-bloom

## REQUIRED PREAMBLE
Read `agents/WGSL_BUILTINS_GENERATIVE.md` before writing WGSL. Rules from it:
- Use the exact 13-binding header and Uniforms struct below.
- In compute: use `textureSampleLevel(..., 0.0)`, `textureLoad(tex, pixel, 0)`, `textureStore(...)`.
- NEVER use `textureSample(`, `dpdx`, `dpdy`, or `tan(`.
- Audio: `bass = plasmaBuffer[0].x; mids = plasmaBuffer[0].y; treble = plasmaBuffer[0].z;`.
- Alpha must encode meaning. Never `vec4(rgb, 1.0)` unless opaque by design.
- End with ACES tone map + IGN dither.

## CREATIVE BRIEF
This shader renders a velocity-sensitive bloom. It already has clean bindings but has zero audio reactivity and an old header. Upgrade it so the bloom **pulses with music**: bass expands the bloom radius and intensity, mids warm the color temperature, treble adds sparkle to high-velocity edges. Preserve the cool blue/pink velocity palette and the anamorphic streak character. The final alpha should encode bloom intensity so it composites cleanly in slot 2/3.

This batch pushes: **modern header + audio reactivity + semantic alpha + ACES/IGN** on every shader.

## DIFFERENTIATE FROM
- `gen-neuro-kinetic-bloom`: already has strong multi-band audio reactivity — don't copy its palette.
- `gen-velocity-bloom` post-upgrade must still feel like a motion-driven bloom, not a generic radial blur.

## OUTPUT CONTRACT (non-negotiable)
1. After the closing ``` of the WGSL block: completely empty. No explanations, no "done".
2. Use the exact 13-binding header below. No `outputTex`, `videoSampler`, `iTime`, `mouse`.
3. Alpha must carry semantic meaning (velocity magnitude or bloom intensity).
4. Use at least two tactics from the 12 Kimi Graphical Tactics (bass_env + ACES + IGN dither recommended).
5. Include a modern Standard Hybrid Header with accurate Category / Features / Chunks From.

## IMMUTABLE 13-BINDING CONTRACT (copy EXACTLY)
```wgsl
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};
```

## CURRENT SOURCE (preserve its soul while upgrading)
```wgsl
// ═══════════════════════════════════════════════════════════════════
//  Velocity Bloom - Velocity-sensitive bloom that intensifies on motion
//  Category: lighting-effects
//  Features: temporal, velocity-based, multi-octave bloom
//  Created: 2026-03-22
//  By: Agent 4A
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

// Calculate velocity magnitude
fn calculateVelocity(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
    let current = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let previous = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    
    // Frame difference
    let diff = current - previous;
    let lumaDiff = length(diff);
    
    // Gradient magnitude for edge detection
    let right = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let left = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).rgb;
    let up = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).rgb;
    let down = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).rgb;
    
    let gradient = length(right - left) + length(up - down);
    
    // Combined velocity estimate
    return lumaDiff + gradient * 0.5;
}

// Multi-octave bloom sampling
fn multiOctaveBloom(uv: vec2<f32>, baseRadius: f32, velocity: f32) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    var totalWeight = 0.0;
    
    // Multiple octaves with different radii
    let octaves = 4;
    for (var o: i32 = 0; o < octaves; o++) {
        let fo = f32(o);
        let radius = baseRadius * (1.0 + fo * 0.5) * (1.0 + velocity);
        let weight = 1.0 / (1.0 + fo * 0.5);
        
        // Sample in star pattern for performance
        let directions = 8;
        for (var i: i32 = 0; i < directions; i++) {
            let angle = f32(i) * 6.28318 / f32(directions);
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius;
            bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb * weight;
        }
        
        totalWeight += weight * f32(directions);
    }
    
    return bloom / totalWeight;
}

// Anamorphic bloom (stretched horizontally)
fn anamorphicBloom(uv: vec2<f32>, radius: f32, velocity: f32) -> vec3<f32> {
    var bloom = vec3<f32>(0.0);
    let samples = 16;
    let stretch = 1.0 + velocity * 2.0;
    
    for (var i: i32 = 0; i < samples; i++) {
        let t = (f32(i) / f32(samples - 1) - 0.5) * 2.0;
        let offset = vec2<f32>(t * radius * stretch, 0.0);
        bloom += textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).rgb;
    }
    
    return bloom / f32(samples);
}

// Velocity-based color tint
fn velocityColor(velocity: f32) -> vec3<f32> {
    // White core, colored aura based on velocity
    if (velocity < 0.3) {
        return mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.8, 0.9, 1.0), velocity / 0.3);
    } else if (velocity < 0.6) {
        return mix(vec3<f32>(0.8, 0.9, 1.0), vec3<f32>(0.4, 0.7, 1.0), (velocity - 0.3) / 0.3);
    } else {
        return mix(vec3<f32>(0.4, 0.7, 1.0), vec3<f32>(0.9, 0.4, 0.8), (velocity - 0.6) / 0.4);
    }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let pixel = 1.0 / resolution;
    let t = u.config.x;
    
    // Parameters - safe randomization
    let threshold = mix(0.0, 0.3, u.zoom_params.x);
    let bloomIntensity = mix(0.3, 2.0, u.zoom_params.y);
    let bloomRadius = mix(0.01, 0.05, u.zoom_params.z);
    let decay = mix(0.7, 0.99, u.zoom_params.w);
    
    // Get base color
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let baseLuma = dot(baseColor, vec3<f32>(0.299, 0.587, 0.114));
    
    // Calculate velocity
    let velocity = calculateVelocity(uv, pixel);
    
    // Determine bloom amount based on velocity
    let velocityMask = smoothstep(threshold, threshold + 0.2, velocity);
    
    // Multi-octave bloom
    let bloom = multiOctaveBloom(uv, bloomRadius, velocity);
    let bloomLuma = dot(bloom, vec3<f32>(0.299, 0.587, 0.114));
    
    // Anamorphic bloom for high velocity areas
    let anamorphic = anamorphicBloom(uv, bloomRadius * 2.0, velocity);
    
    // Combine blooms
    var finalBloom = mix(bloom, anamorphic, velocityMask * 0.5);
    
    // Apply velocity-based color tint to bloom
    let tint = velocityColor(velocity);
    finalBloom = finalBloom * tint;
    
    // Previous bloom accumulation for decay
    let prevBloom = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    let decayedBloom = prevBloom * decay;
    
    // Accumulate bloom with decay
    let accumulatedBloom = max(finalBloom * bloomIntensity, decayedBloom * 0.9);
    
    // Composite: base + bloom
    // Use screen blend for light areas, add for motion areas
    let screenBlend = 1.0 - (1.0 - baseColor) * (1.0 - accumulatedBloom);
    let addBlend = baseColor + accumulatedBloom * velocityMask;
    
    var finalColor = mix(screenBlend, addBlend, velocityMask * 0.5);
    
    // Boost brightness in high-velocity areas
    finalColor = finalColor * (1.0 + velocity * 0.3);
    
    // Store accumulated bloom for next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(accumulatedBloom, 1.0));
    
    // Alpha based on effect intensity
    let alpha = mix(0.8, 1.0, velocityMask);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

## ROLE TOOLKIT — Algorithmist + Visualist
- Add `bass`, `mids`, `treble` reads from `plasmaBuffer[0]`.
- Modulate `bloomRadius`, `bloomIntensity`, and decay with audio envelopes.
- Add a subtle color temperature shift on mids (warmer when mids are high).
- Add treble-driven sparkle on high-velocity edges.
- Replace Reinhard-ish tone map with `acesToneMap` + `ign` dither.
- Ensure final write uses premultiplied alpha when alpha < 1.0.

## 12 KIMI GRAPHICAL TACTICS (apply where appropriate)
```wgsl
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}
fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}
```
Use depth-aware fog, anti-moiré LOD, polar kaleidoscope fold, and hex bokeh taps as needed.

## LINE BUDGET & FINAL REMINDER
Target: ≤ 200 lines. Preserve the original velocity-bloom character; do not turn it into a different effect.

Stop the moment the WGSL fence closes. Nothing after it.
