// ═══════════════════════════════════════════════════════════════════
//  Watercolor Bloom
//  Category: image
//  Features: audio-reactive, temporal, upgraded-rgba, semantic-alpha
//  Complexity: Medium
//  Created: 2026-05-30
// ═══════════════════════════════════════════════════════════════════
//  Applies a soft, feathered watercolor bloom using multi-tap
//  Gaussian-like blurring, paper texture, and wet-edge darkening.
//  The bloom radius and paper absorption expand with audio energy.
//  Temporal feedback (dataTextureC) lets wet paint slowly dry.
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
  config: vec4<f32>,      // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>, // x=BloomRadius, y=WetEdge, z=PaperTexture, w=DrySpeed
  ripples: array<vec4<f32>, 50>,
};

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// 2D paper-fibre noise (multi-octave)
fn paperNoise(uv: vec2<f32>, scale: f32) -> f32 {
    let p = uv * scale;
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

// Gaussian weighted tap blur
fn bloomSample(uv: vec2<f32>, offset: vec2<f32>, weight: f32) -> vec4<f32> {
    return textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999)), 0.0) * weight;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let ps    = 1.0 / dims;
    let time  = u.config.x;

    // Audio
    let audio  = plasmaBuffer[0].xyz;
    let bass   = audio.x;
    let mid    = audio.y;

    // Params
    let bloomR    = mix(0.003, 0.025, u.zoom_params.x) * (1.0 + bass * 2.0);
    let wetEdge   = mix(0.0, 1.0, u.zoom_params.y);
    let paperStr  = mix(0.0, 0.25, u.zoom_params.z);
    let dryRate   = mix(0.01, 0.18, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let held = step(0.5, u.zoom_config.w);
    let aspect = dims.x / dims.y;
    let mouseDelta = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let wetBrush = (1.0 - smoothstep(0.04, 0.32, length(mouseDelta))) * held;

    var clickBloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var rippleIndex = 0u; rippleIndex < rippleCount; rippleIndex = rippleIndex + 1u) {
        let ripple = u.ripples[rippleIndex];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickBloom += smoothstep(0.026, 0.0, abs(length(delta) - age * 0.36)) * exp(-age * 1.35);
        }
    }

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Multi-tap bloom kernel (13-tap approximation)
    let OFFSETS = array<vec2<f32>, 13>(
        vec2<f32>( 0.0,  0.0),
        vec2<f32>( 1.0,  0.0), vec2<f32>(-1.0,  0.0),
        vec2<f32>( 0.0,  1.0), vec2<f32>( 0.0, -1.0),
        vec2<f32>( 1.0,  1.0), vec2<f32>(-1.0,  1.0),
        vec2<f32>( 1.0, -1.0), vec2<f32>(-1.0, -1.0),
        vec2<f32>( 2.0,  0.0), vec2<f32>(-2.0,  0.0),
        vec2<f32>( 0.0,  2.0), vec2<f32>( 0.0, -2.0)
    );
    let WEIGHTS = array<f32, 13>(
        0.2, 0.1, 0.1, 0.1, 0.1,
        0.05, 0.05, 0.05, 0.05,
        0.025, 0.025, 0.025, 0.025
    );

    var bloom = vec4<f32>(0.0);
    for (var i = 0; i < 13; i++) {
        bloom += bloomSample(uv, OFFSETS[i] * ps * (bloomR / ps.x) * (1.0 + wetBrush * 0.5 + clickBloom * 0.4), WEIGHTS[i]);
    }

    // Watercolor pigment: desaturate slightly, push toward warm tones
    let luma = dot(bloom.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let desat = mix(bloom.rgb, vec3<f32>(luma), 0.15);
    let warm  = desat + vec3<f32>(0.02, 0.01, -0.02) * (1.0 - luma);

    // Paper texture
    let paper = paperNoise(uv, 80.0) * paperStr;
    var col   = warm * (1.0 - paper * 0.5) + vec3<f32>(paper * 0.03);
    let pigmentRunner = pow(max(0.0, sin(uv.x * 63.0 + uv.y * 29.0 - time * 15.0)), 14.0);
    col += vec3<f32>(0.12, 0.05, 0.16) * pigmentRunner * (0.08 + audio.z * 0.14 + wetBrush * 0.12);

    // Wet-edge darkening: darken near the brightest/darkest transition
    let edgeDark = 1.0 - wetEdge * smoothstep(0.3, 0.7, luma) * 0.5;
    col *= edgeDark;

    // Advect wet pigment along a smooth diagonal flow, then let it dry.
    let wetFlow = vec2<f32>(sin(uv.y * 18.0 + time * 2.0), -1.0) * (1.0 + wetBrush * 2.0 + mid);
    let historyCoord = clamp(coord - vec2<i32>(round(wetFlow)), vec2<i32>(0), vec2<i32>(dims) - vec2<i32>(1));
    let prev = textureLoad(dataTextureC, historyCoord, 0);
    let retention = clamp(1.0 - dryRate + wetBrush * 0.04, 0.0, 0.995);
    let freshPigment = vec4<f32>(col + vec3<f32>(0.12, 0.04, 0.08) * clickBloom, bloom.a);
    let accumulated = mix(freshPigment, prev, retention * (1.0 - mid * 0.1));
    var finalColor  = accumulated;

    // Semantic alpha
    let alpha = clamp(src.a * (0.85 + luma * 0.15), 0.0, 1.0);
    finalColor.a = alpha;

    finalColor = vec4<f32>(clamp(finalColor.rgb, vec3<f32>(0.0), vec3<f32>(4.0)), alpha);
    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(luma, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, finalColor);
    textureStore(dataTextureB, coord, finalColor);
}
