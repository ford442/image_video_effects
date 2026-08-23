// ═══════════════════════════════════════════════════════════════════
//  Chroma Vortex
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, audio-driven,
//            spiral-sdf, multi-vortex, spectral-ramp, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-06-28
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Twist, y=Spread, z=Radius, w=CenterBias
  ripples: array<vec4<f32>, 50>,
};

const TAU: f32 = 6.28318530717958647692;

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(hsv.z - c);
}

// ── Spiral SDF mask for vortex feathering ────────────────────────
fn sdSpiral(p: vec2<f32>, arms: f32, tightness: f32) -> f32 {
    let r = length(p);
    let a = atan2(p.y, p.x);
    let spiralTarget = arms * r * tightness;
    let seg = abs(fract((a + spiralTarget) / TAU) - 0.5) * TAU;
    return seg;
}

// ── Spectral color ramp for vortex tinting ───────────────────────
fn spectralRamp(t: f32) -> vec3<f32> {
    return hsv2rgb(vec3<f32>(fract(t), 0.85, 1.0));
}

// ─────────────────────────────────────────────────────────────────────────────
// ACES Tone Mapping
// ─────────────────────────────────────────────────────────────────────────────
fn aces_tonemap(color: vec3<f32>) -> vec3<f32> {
    let m1 = mat3x3<f32>(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777
    );
    let m2 = mat3x3<f32>(
        1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602
    );
    let v = m1 * color;
    let a = v * (v + 0.0245786) - 0.000090537;
    let b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let nParams = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));
    let twist = nParams.x * TAU * 2.0 * (1.0 + bass * 0.2 + mids * 0.1);
    let spread = nParams.y * 0.1 * (1.0 + treble * 0.1);
    let radius = max(nParams.z, 0.01);
    let centerBias = nParams.w;

    // Base color for alpha preservation
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Multi-vortex centers: mouse + an orbiting secondary center
    let c1 = mousePos;
    let c2 = vec2<f32>(0.5) + 0.35 * vec2<f32>(cos(time * 0.4 + bass * 2.0),
                                                 sin(time * 0.3 + mids * 2.0));
    let centers = array<vec2<f32>, 2>(c1, c2);
    let weights = array<f32, 2>(1.0, 0.6);

    var accColor = vec3<f32>(0.0);
    var accWeight = 0.0;
    var totalFactor = 0.0;

    for (var i = 0; i < 2; i = i + 1) {
        let center = centers[i];
        let diff = uv - center;
        let dist = length(vec2<f32>(diff.x * aspect, diff.y));

        var factor = smoothstep(radius, 0.0, dist);
        let power = centerBias * 4.8 + 0.2;
        factor = pow(factor, power);

        let angleBase = factor * twist;
        let angleR = angleBase - spread * factor * 10.0;
        let angleG = angleBase;
        let angleB = angleBase + spread * factor * 10.0;

        let diffA = vec2<f32>(diff.x * aspect, diff.y);
        let rotR_sq = rotate(diffA, angleR);
        let rotG_sq = rotate(diffA, angleG);
        let rotB_sq = rotate(diffA, angleB);

        let uvR = clamp(center + vec2<f32>(rotR_sq.x / aspect, rotR_sq.y),
                        vec2<f32>(0.0), vec2<f32>(1.0));
        let uvG = clamp(center + vec2<f32>(rotG_sq.x / aspect, rotG_sq.y),
                        vec2<f32>(0.0), vec2<f32>(1.0));
        let uvB = clamp(center + vec2<f32>(rotB_sq.x / aspect, rotB_sq.y),
                        vec2<f32>(0.0), vec2<f32>(1.0));

        let col = vec3<f32>(
            textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r,
            textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g,
            textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b
        );

        let w = weights[i] * (0.3 + factor);
        accColor = accColor + col * w;
        accWeight = accWeight + w;
        totalFactor = totalFactor + factor * weights[i];
    }

    var color = accColor / max(accWeight, 1e-4);

    // Spiral SDF mask overlaid across the frame
    let spiralCenter = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    let spiralDist = sdSpiral(spiralCenter, 3.0 + centerBias * 5.0,
                              8.0 + twist * 0.5);
    let spiralMask = smoothstep(0.15, 0.0, spiralDist);

    // Spectral ramp driven by depth and vortex intensity
    let ramp = spectralRamp(depth + totalFactor * 0.5 + time * 0.02);
    color = mix(color, color * ramp + ramp * 0.2, spiralMask * 0.5 + totalFactor * 0.3);

    // Alpha: preserve input transparency while blending vortex intensity
    let finalAlpha = mix(baseColor.a, 1.0, clamp(totalFactor * 0.7, 0.0, 1.0));

    textureStore(writeTexture, coord, vec4<f32>(aces_tonemap(color), finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0, 0, 1));
    textureStore(dataTextureA, coord, vec4<f32>(color, finalAlpha));
}
