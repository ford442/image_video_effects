// ═══════════════════════════════════════════════════════════════════
//  Fluid Grid
//  Category: distortion
//  Features: mouse-driven, audio-reactive, curl-noise, divergence-free, upgraded-rgba
//  Complexity: High
//  Chunks From: fluid-grid, curl2D, fbm, bass_env
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridSize, y=FlowSpeed, z=Distortion, w=Turbulence
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  let a = hash21(i);
  let b = hash21(i + vec2<f32>(1.0, 0.0));
  let c = hash21(i + vec2<f32>(0.0, 1.0));
  let d = hash21(i + vec2<f32>(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var sum = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    sum = sum + amp * valueNoise(p * freq);
    freq = freq * 2.0;
    amp = amp * 0.5;
  }
  return sum;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = fbm(p + vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n2 = fbm(p - vec2<f32>(eps, 0.0) + t * 0.1, 3);
  let n3 = fbm(p + vec2<f32>(0.0, eps) + t * 0.1, 3);
  let n4 = fbm(p - vec2<f32>(0.0, eps) + t * 0.1, 3);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Weighted grid attractor with explicit initialization: top-left is a
    // valid normalized cursor location, not an empty-state sentinel.
    let rawMouse = u.zoom_config.yz;
    var gridCenter = vec2<f32>(extraBuffer[133u], extraBuffer[134u]);
    var gridVelocity = vec2<f32>(extraBuffer[135u], extraBuffer[136u]);
    let gridInitialized = extraBuffer[137u] >= 0.5;
    if (!gridInitialized) {
        gridCenter = rawMouse;
        gridVelocity = vec2<f32>(0.0);
    }
    let springDt = select(0.0, clamp(time - extraBuffer[138u], 0.0005, 0.05), gridInitialized);
    let springOmega = 9.0;
    let gridAccel = springOmega * springOmega * (rawMouse - gridCenter)
        - 2.0 * springOmega * gridVelocity;
    gridVelocity += gridAccel * springDt;
    gridCenter = clamp(gridCenter + gridVelocity * springDt, vec2<f32>(-0.2), vec2<f32>(1.2));
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133u] = gridCenter.x;
        extraBuffer[134u] = gridCenter.y;
        extraBuffer[135u] = gridVelocity.x;
        extraBuffer[136u] = gridVelocity.y;
        extraBuffer[137u] = 1.0;
        extraBuffer[138u] = time;
    }

    // Rewire the old mislabeled controls while preserving their default look:
    // Flow Speed now drives curl time (0.5 -> legacy 0.15), and Turbulence
    // now drives curl strength (0.5 -> legacy 1.0 multiplier).
    let gridSize = 10.0 + u.zoom_params.x * 90.0 * bass_env(bass, mids);
    let flowSpeed = mix(0.05, 0.25, u.zoom_params.y);
    let repulsion = u.zoom_params.z;
    let turbulence = mix(0.5, 1.5, u.zoom_params.w);
    let legacyViscosity = 0.5;
    let legacyRestitution = 0.5;

    let tileUV = floor(uv * gridSize) / gridSize;
    let tileCenter = tileUV + vec2<f32>(0.5 / gridSize, 0.5 / gridSize);
    let distVec = tileCenter - gridCenter;
    let distVecCorrected = distVec * aspectVec;
    let dist = length(distVecCorrected);
    let offsetDir = distVecCorrected / max(dist, 0.001);
    let push = smoothstep(0.45 + legacyRestitution * 0.1, 0.0, dist)
        * repulsion * (0.12 + bass * 0.04);

    let cellCoord = vec2<u32>(floor(clamp(tileUV * gridSize, vec2<f32>(0.0), vec2<f32>(65535.0))));
    let cellBand = (cellCoord.x + cellCoord.y) % 8u;
    let cellVoice = plasmaBuffer[(cellBand % 8u) + 1u].x;
    let curl = curl2D(uv * (2.2 + turbulence * 0.6), time * flowSpeed)
        * 0.03 * turbulence * bass_env(bass, mids) * (1.0 + cellVoice * 0.25);
    var uvOffset = vec2<f32>(offsetDir.x / aspect, offsetDir.y) * push + curl;

    // Clicks inject localized, alternating eddies into the otherwise smooth
    // grid flow. Directions are computed in aspect space and mapped to UV.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri += 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.8) {
            let clickVec = (uv - ripple.xy) * aspectVec;
            let clickDist = length(clickVec);
            let tangentAspect = vec2<f32>(-clickVec.y, clickVec.x) / max(clickDist, 0.001);
            let tangentUV = tangentAspect / aspectVec;
            let directionSign = select(-1.0, 1.0, (ri % 2u) == 0u);
            let eddy = exp(-age * 1.8) * smoothstep(0.28, 0.0, clickDist);
            uvOffset += tangentUV * directionSign * eddy * 0.035 * turbulence;
        }
    }
    let sampleUV = clamp(uv - uvOffset, vec2<f32>(0.001, 0.001), vec2<f32>(0.999, 0.999));

    let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let gridLine = fract(uv * gridSize);
    let cellEdge = min(min(gridLine.x, 1.0 - gridLine.x), min(gridLine.y, 1.0 - gridLine.y));
    let lineWeight = 0.015 + (1.0 - legacyViscosity) * 0.035;
    let lineMask = 1.0 - smoothstep(lineWeight, lineWeight + 0.01, cellEdge);

    let flowColor = vec3<f32>(0.05 + treble * 0.1, 0.15 + mids * 0.1, 0.28 + bass * 0.1)
        * lineMask * (1.0 + cellVoice * 0.2);
    let finalColor = mix(baseColor.rgb, baseColor.rgb * 0.45 + flowColor, lineMask * 0.7);
    let alpha = clamp(baseColor.a * 0.45 + push * 1.8 + lineMask * 0.12 + bass * 0.05, 0.08, 1.0);

    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r + push * 0.2, 0.0, 1.0);
    let finalPixel = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalPixel);
}
