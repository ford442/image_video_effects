// ═══════════════════════════════════════════════════════════════════
//  Slime Mold on Video
//  Category: simulation
//  Features: mouse-driven, audio-reactive, temporal-trail, depth-glow, chromatic-tendril, upgraded-rgba
//  Complexity: High
//  Chunks From: slime-mold-on-video, bass_env
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn lumaAt(uv: vec2<f32>, readTexture: texture_2d<f32>, u_sampler: sampler) -> f32 {
  return dot(textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn trailAt(uv: vec2<f32>, dataTextureC: texture_2d<f32>, u_sampler: sampler) -> f32 {
  return textureSampleLevel(dataTextureC, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (gid.x >= u32(res.x) || gid.y >= u32(res.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let coord = vec2<i32>(gid.xy);
    let px = 1.0 / res;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthGlow = mix(0.6, 1.4, depth);

    let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let trail = textureLoad(dataTextureC, coord, 0).r;

    var blur = 0.0;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let sampleUV = uv + vec2<f32>(f32(x), f32(y)) * px;
            blur = blur + trailAt(sampleUV, dataTextureC, u_sampler);
        }
    }
    blur = blur / 9.0;

    let food = lumaAt(uv, readTexture, u_sampler);
    let foodL = lumaAt(uv - vec2<f32>(px.x, 0.0), readTexture, u_sampler);
    let foodR = lumaAt(uv + vec2<f32>(px.x, 0.0), readTexture, u_sampler);
    let foodD = lumaAt(uv - vec2<f32>(0.0, px.y), readTexture, u_sampler);
    let foodU = lumaAt(uv + vec2<f32>(0.0, px.y), readTexture, u_sampler);

    let trailL = trailAt(uv - vec2<f32>(px.x, 0.0), dataTextureC, u_sampler);
    let trailR = trailAt(uv + vec2<f32>(px.x, 0.0), dataTextureC, u_sampler);
    let trailD = trailAt(uv - vec2<f32>(0.0, px.y), dataTextureC, u_sampler);
    let trailU = trailAt(uv + vec2<f32>(0.0, px.y), dataTextureC, u_sampler);

    let gradFood = vec2<f32>(foodR - foodL, foodU - foodD);
    let gradTrail = vec2<f32>(trailR - trailL, trailU - trailD);

    let jitter = vec2<f32>(
        sin(u.config.x * 0.9 + uv.y * 33.0),
        cos(u.config.x * 1.1 + uv.x * 29.0)
    ) * 0.015 * bass_env(bass, mids);

    let drift = normalize(gradFood * 2.3 + gradTrail * 1.2 + jitter + vec2<f32>(1e-4));
    let aheadUV = clamp(uv + drift * px * 2.0, vec2<f32>(0.0), vec2<f32>(1.0));
    let aheadTrail = trailAt(aheadUV, dataTextureC, u_sampler);

    let follow = mix(0.05, 0.80, clamp(u.zoom_params.x, 0.0, 1.0));
    let decay = mix(0.88, 0.995, clamp(u.zoom_params.y, 0.0, 1.0));
    let foodGain = mix(0.01, 0.20, clamp(u.zoom_params.z, 0.0, 1.0));
    let glowGain = mix(0.25, 1.50, clamp(u.zoom_params.w, 0.0, 1.0)) * depthGlow;

    var deposit = max(food - 0.25, 0.0) * foodGain;

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseBoost = smoothstep(0.10, 0.0, length(uv - mousePos)) * mouseDown;
    deposit = deposit + mouseBoost * 0.12 * (1.0 + bass * 0.5);

    var nextTrail = max(blur * decay, aheadTrail * follow) + deposit;
    nextTrail = clamp(nextTrail, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(nextTrail, food, drift.x * 0.5 + 0.5, drift.y * 0.5 + 0.5));

    // Chromatic tendrils: bass shifts green, mids shift cyan, treble shifts magenta
    let tendrilR = 0.07 + bass * 0.03;
    let tendrilG = 0.95 + mids * 0.05;
    let tendrilB = 0.62 + treble * 0.05;
    let tendril = vec3<f32>(tendrilR, tendrilG, tendrilB) * nextTrail;
    let hot = vec3<f32>(1.0, 0.55, 0.20) * pow(nextTrail, 2.2) * glowGain;
    let finalColor = clamp(mix(base.rgb, base.rgb * 0.35 + tendril + hot, nextTrail), vec3<f32>(0.0), vec3<f32>(1.0));
    let alpha = clamp(nextTrail + 0.2 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
