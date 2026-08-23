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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
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
    let held = select(0.62, 1.0, u.zoom_config.w > 0.5);
    let push = smoothstep(0.45 + legacyRestitution * 0.1, 0.0, dist)
        * repulsion * (0.12 + bass * 0.04) * held;

    let cellCoord = vec2<u32>(floor(clamp(tileUV * gridSize, vec2<f32>(0.0), vec2<f32>(65535.0))));
    let cellBand = (cellCoord.x + cellCoord.y) % 8u;
    let cellVoice = plasmaBuffer[(cellBand % 8u) + 1u].x;
    let curlDomain = uv * (2.2 + turbulence * 0.6);
    let curlRaw = curl2D(curlDomain, time * flowSpeed);
    let curl = curlRaw * 0.03 * turbulence * bass_env(bass, mids) * (1.0 + cellVoice * 0.25);
    var uvOffset = vec2<f32>(offsetDir.x / aspect, offsetDir.y) * push + curl;

    // Depth contours behave like submerged obstacles in the grid flow.
    let pixel = vec2<i32>(global_id.xy);
    let dims = vec2<i32>(resolution);
    let dL = textureLoad(readDepthTexture, clamp(pixel + vec2<i32>(-1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    let dR = textureLoad(readDepthTexture, clamp(pixel + vec2<i32>(1, 0), vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    let dD = textureLoad(readDepthTexture, clamp(pixel + vec2<i32>(0, -1), vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    let dU = textureLoad(readDepthTexture, clamp(pixel + vec2<i32>(0, 1), vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    let depthTangent = vec2<f32>(dU - dD, dL - dR);
    uvOffset += depthTangent * repulsion * 0.035;

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

    // Draw the lattice in the deformed domain. Major rails, minor rails, and
    // glowing junctions retain different weights under local strain.
    let deformedGrid = sampleUV * gridSize;
    let gridLine = fract(deformedGrid);
    let cellEdge = min(min(gridLine.x, 1.0 - gridLine.x), min(gridLine.y, 1.0 - gridLine.y));
    let lineWeight = 0.015 + (1.0 - legacyViscosity) * 0.035;
    let minorMask = 1.0 - smoothstep(lineWeight, lineWeight + 0.012, cellEdge);
    let majorLine = fract(deformedGrid / 5.0);
    let majorEdge = min(min(majorLine.x, 1.0 - majorLine.x), min(majorLine.y, 1.0 - majorLine.y));
    let majorMask = 1.0 - smoothstep(lineWeight * 0.75, lineWeight * 0.75 + 0.01, majorEdge);
    let junction = pow(clamp((1.0 - smoothstep(0.08, 0.18, abs(gridLine.x - 0.5)))
        * (1.0 - smoothstep(0.08, 0.18, abs(gridLine.y - 0.5))), 0.0, 1.0), 2.0);
    let curlX = curl2D(curlDomain + vec2<f32>(0.025, 0.0), time * flowSpeed);
    let curlY = curl2D(curlDomain + vec2<f32>(0.0, 0.025), time * flowSpeed);
    let strain = clamp((length(curlX - curlRaw) + length(curlY - curlRaw))
        * 0.16 * turbulence, 0.0, 1.0);
    let lineMask = clamp(minorMask * 0.62 + majorMask * 0.72 + junction * (0.18 + strain), 0.0, 1.0);

    let flowColor = (vec3<f32>(0.05 + treble * 0.1, 0.15 + mids * 0.1, 0.28 + bass * 0.1)
        * minorMask + vec3<f32>(0.18, 0.58, 0.92) * majorMask
        + vec3<f32>(0.85, 0.94, 1.1) * junction * (0.45 + treble * 0.8))
        * (1.0 + cellVoice * 0.2 + strain * 0.35);
    var finalColor = mix(baseColor.rgb, baseColor.rgb * 0.42 + flowColor, lineMask * 0.78);
    let alphaLive = clamp(baseColor.a * 0.45 + push * 1.8 + lineMask * 0.16
        + junction * 0.12 + bass * 0.05, 0.08, 1.0);

    // Exact display history follows the local velocity field, giving stretched
    // rails and junction afterimages while A stays the authoritative display.
    let historyDrift = vec2<i32>(round((uvOffset * resolution) * mix(0.08, 0.22, turbulence)));
    let prev = textureLoad(dataTextureC, clamp(pixel - historyDrift, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    let historyWeight = clamp((0.12 + turbulence * 0.24 + strain * 0.15) * lineMask, 0.0, 0.55);
    finalColor = mix(finalColor, prev.rgb * 0.965, historyWeight);
    let alpha = mix(alphaLive, prev.a * 0.96, historyWeight * 0.5);

    let sourceDepth = textureLoad(readDepthTexture, pixel, 0).r;
    let depth = clamp(sourceDepth * 0.86 + push * 0.2 + lineMask * 0.08 + strain * 0.06, 0.0, 1.0);
    let finalPixel = vec4<f32>(acesToneMap(finalColor), alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalPixel);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(min(finalColor, vec3<f32>(7.0)), alpha));
}
