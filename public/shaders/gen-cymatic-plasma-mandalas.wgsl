// ═══════════════════════════════════════════════════════════════════
//  Cymatic Plasma-Mandalas
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-aberration,
//            temporal-symmetry-memory, audio-cymatic-frequency, depth-edge-glow
//  Complexity: High
//  Created: 2026-05-10
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn fold(uv: vec2<f32>, symmetryOrder: f32) -> vec2<f32> {
    let radius = length(uv);
    let angle = atan2(uv.y, uv.x);
    let sector = 6.2831853 / symmetryOrder;
    let foldedAngle = angle - sector * floor((angle + sector * 0.5) / sector);
    return vec2<f32>(cos(foldedAngle), sin(foldedAngle)) * radius;
}

fn sdPolygon(p: vec2<f32>, sides: f32) -> f32 {
    let a = atan2(p.y, p.x);
    let b = 6.2831853 / sides;
    let modA = a - b * floor((a + b * 0.5) / b);
    return length(p) * cos(modA);
}

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn getPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

fn applyChromaticAberration(distR: f32, distG: f32, distB: f32, density: f32) -> vec3<f32> {
    let plasmaR = exp(-abs(distR) * (20.0 / density));
    let plasmaG = exp(-abs(distG) * (20.0 / density));
    let plasmaB = exp(-abs(distB) * (20.0 / density));
    return vec3<f32>(plasmaR, plasmaG, plasmaB);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(global_id.xy);
    var uv = (fragCoord * 2.0 - dims) / min(dims.x, dims.y);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Audio-driven cymatic frequency modulation
    let symmetryOrder = u.zoom_params.x * (1.0 + bass * 0.3);
    let plasmaDensity = u.zoom_params.y;
    let cymaticFreq = u.zoom_params.z * (1.0 + mids * 0.5);
    let swirlChaos = u.zoom_params.w;

    let t = u.config.x * 0.5;
    let audio = bass * 0.05;

    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    let mouse = vec2<f32>(mX, mY);

    let mDist = length(uv - mouse);
    let swirlStrength = exp(-mDist * 2.0) * swirlChaos;
    let swirlAngle = swirlStrength * sin(t + mDist * 10.0);
    let s = sin(swirlAngle);
    let c = cos(swirlAngle);
    let rotMat = mat2x2<f32>(c, -s, s, c);
    uv = rotMat * uv;

    let foldedUv = fold(uv, symmetryOrder);
    let radius = length(uv);
    let angle = atan2(uv.y, uv.x);
    let sector = 6.2831853 / symmetryOrder;
    let foldedAngle = angle - sector * floor((angle + sector * 0.5) / sector);

    let wave = sin(radius * cymaticFreq - t * 2.0 + audio * 5.0 + mids * 0.5) * cos(foldedAngle * symmetryOrder + t);
    var d = sdPolygon(foldedUv, 6.0) - 0.4 - wave * 0.1;
    d = min(d, sdCircle(foldedUv - vec2<f32>(0.5, 0.0), 0.2 - wave * 0.05));
    d = d + sin(d * 10.0 - t * 3.0 + audio * 10.0 + treble * 2.0) * 0.02;

    let colorBase = getPalette(radius * 0.5 - t * 0.2 + audio);

    let distR = d - 0.01 * plasmaDensity * (1.0 + bass * 0.3);
    let distG = d;
    let distB = d + 0.01 * plasmaDensity * (1.0 + treble * 0.3);

    let aberration = applyChromaticAberration(distR, distG, distB, plasmaDensity);
    var col = colorBase * aberration;

    col = col + vec3<f32>(1.0, 0.8, 0.9) * exp(-length(uv) * 5.0) * (0.5 + audio * 0.5 + treble * 0.2);

    // Temporal symmetry memory: previous frame burns into current
    let prev = textureSampleLevel(dataTextureC, u_sampler, (fragCoord / dims), 0.0).rgb;
    let symMemory = mix(col, prev * 0.9, 0.06 + bass * 0.02);
    col = mix(col, symMemory, 0.5);

    // Depth-aware edge glow: read depth and modulate edge intensity
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, fragCoord / dims, 0.0).r;
    let edgeGlow = smoothstep(0.05, 0.0, abs(d)) * (0.5 + depth * 0.5);
    col += vec3<f32>(0.4, 0.7, 0.9) * edgeGlow * treble;

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.2 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(col, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);

    let depth_uv = clamp(vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w), vec2<f32>(0.0), vec2<f32>(1.0));
    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, depth_uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
}
