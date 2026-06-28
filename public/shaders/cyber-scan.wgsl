// ═══════════════════════════════════════════════════════════════════
//  Cyber Scan
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, temporal-scan-pass, depth-colorize, chromatic-scan, upgraded-rgba,
//            holographic-scanlines, data-visualization, hex-grid, interference-patterns
//  Complexity: Very High
//  Chunks From: cyber-scan, bass_env
//  Created: 2024-01-01
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const PHI: f32 = 1.61803398875;

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn hash12(p: vec2<f32>) -> f32 {
  let h = sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453;
  return fract(h);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453;
  return fract(h);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
    mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
    u.y
  );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var total = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i = 0; i < octaves; i = i + 1) {
    total = total + amplitude * noise2(p * frequency);
    amplitude = amplitude * 0.5;
    frequency = frequency * 2.1;
  }
  return total;
}

fn hexGrid(p: vec2<f32>, size: f32) -> vec3<f32> {
  let axial = vec2<f32>(1.7320508, 1.0);
  let scaled = p * size;
  let gridA = (fract(scaled / axial) - 0.5) * axial;
  let idA = floor(scaled / axial);
  let shifted = scaled - axial * 0.5;
  let gridB = (fract(shifted / axial) - 0.5) * axial;
  let idB = floor(shifted / axial);
  let distA = dot(gridA, gridA);
  let distB = dot(gridB, gridB);
  let useB = distB < distA;
  let local = select(gridA, gridB, useB);
  let cellId = select(idA, idB, useB);
  return vec3<f32>(local, hash12(cellId));
}

fn binaryRain(uv: vec2<f32>, time: f32, speed: f32, density: f32) -> f32 {
  let col = floor(uv.x * density);
  let row = floor(uv.y * density * 2.0);
  let dropSpeed = hash12(vec2<f32>(col, 0.0)) * speed + speed * 0.5;
  let dropPos = fract(uv.y * density * 2.0 + time * dropSpeed + hash12(vec2<f32>(col, 1.0)) * 10.0);
  let char = hash12(vec2<f32>(col, row + floor(time * dropSpeed * 2.0)));
  let brightness = smoothstep(0.85, 0.95, char) * smoothstep(0.0, 0.15, dropPos) * smoothstep(1.0, 0.7, dropPos);
  return brightness;
}

fn interferencePattern(uv: vec2<f32>, freq: f32, time: f32) -> f32 {
  let d1 = length(uv - vec2<f32>(0.3, 0.5));
  let d2 = length(uv - vec2<f32>(0.7, 0.5));
  let wave1 = sin(d1 * freq * TAU - time * 3.0);
  let wave2 = sin(d2 * freq * TAU - time * 2.5);
  return (wave1 + wave2) * 0.5 + 0.5;
}

fn holographicLines(uv: vec2<f32>, time: f32, bass: f32) -> f32 {
  let lineFreq = 80.0 + bass * 40.0;
  let lines = sin(uv.y * lineFreq + time * 2.0) * 0.5 + 0.5;
  let scan = sin(uv.x * 200.0 + time * 5.0) * 0.5 + 0.5;
  return lines * 0.3 + scan * 0.1;
}

fn hueToRGB(hue: f32) -> vec3<f32> {
  let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
  let p = abs(fract(vec3<f32>(hue) + k) * 6.0 - vec3<f32>(3.0));
  return clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthColorize = mix(0.5, 1.5, depth);

    let scanSpeed = u.zoom_params.x * bass_env(bass, mids);
    let trailLength = u.zoom_params.y;
    let scanWidth = u.zoom_params.z;
    let colorShiftAmt = u.zoom_params.w;

    // Primary scan line
    let scanLine = fract(mousePos.x + time * scanSpeed);
    let dist = abs(uv.x - scanLine);

    // Secondary scan lines (multi-layer)
    let scanLine2 = fract(mousePos.x + time * scanSpeed * 1.618 + 0.33);
    let scanLine3 = fract(mousePos.x + time * scanSpeed * 0.618 + 0.67);
    let dist2 = abs(uv.x - scanLine2);
    let dist3 = abs(uv.x - scanLine3);

    let w = scanWidth * (1.0 + bass * 0.3);
    let intensity = smoothstep(w, 0.0, dist);
    let intensity2 = smoothstep(w * 1.5, 0.0, dist2) * 0.5;
    let intensity3 = smoothstep(w * 2.0, 0.0, dist3) * 0.3;
    let totalIntensity = intensity + intensity2 + intensity3;

    let trail = smoothstep(w * 5.0, w, dist) * trailLength;
    let trail2 = smoothstep(w * 7.0, w * 1.5, dist2) * trailLength * 0.5;
    let totalTrail = trail + trail2;

    // Temporal scan: previous pass smears vertically
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let smear = mix(prev.rgb * 0.85, vec3<f32>(0.0), 0.15);

    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(sourceColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));

    // Depth colorize: near objects get warm scan, far objects get cool scan
    let nearHue = 0.02 + bass * 0.05;
    let farHue = 0.55 - mids * 0.1;
    let hue = mix(farHue, nearHue, depth);
    let scanColor = vec3<f32>(0.9, 0.85, 0.8) * mix(vec3<f32>(1.0), hueToRGB(hue), 0.7);

    // Holographic scanlines overlay
    let holoLines = holographicLines(uv, time, bass);

    // Hex grid data visualization
    let hex = hexGrid(uv * vec2<f32>(aspect, 1.0), 12.0 + mids * 8.0);
    let hexEdge = 1.0 - smoothstep(0.35, 0.42, length(hex.xy));
    let hexData = hex.z * hexEdge * (0.1 + treble * 0.2);

    // Binary rain effect
    let binaryRain = binaryRain(uv, time, 0.5 + bass * 0.5, 30.0 + mids * 20.0);

    // Interference pattern
    let interference = interferencePattern(uv, 3.0 + bass * 2.0, time);

    // FBM noise overlay for data corruption feel
    let noiseOverlay = fbm(uv * 8.0 + time * 0.3, 5) * 0.1;

    // Chromatic scan: treble shifts RGB channels horizontally
    let chroma = colorShiftAmt * treble * 0.02;
    let rUV = clamp(uv + vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv - vec2<f32>(chroma, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let g = sourceColor.g;

    let chromaSource = vec3<f32>(r, g, b);
    var rgb = mix(chromaSource, scanColor, totalIntensity * 0.5);
    rgb = mix(rgb, smear, totalTrail * 0.3);
    rgb = rgb + scanColor * totalIntensity * 0.8 * depthColorize;

    // Add holographic lines
    rgb = rgb + vec3<f32>(0.1, 0.9, 1.0) * holoLines * intensity * (0.2 + treble * 0.3);

    // Add hex grid data
    rgb = rgb + vec3<f32>(0.0, 0.8, 1.0) * hexData * (0.1 + bass * 0.1);

    // Add binary rain
    rgb = rgb + vec3<f32>(0.0, 1.0, 0.3) * binaryRain * 0.15 * intensity;

    // Add interference
    rgb = rgb + scanColor * interference * 0.1 * intensity;

    // Add noise corruption
    rgb = rgb + vec3<f32>(noiseOverlay * intensity * 0.3);

    // Sparkle on scan line intersection with high frequencies
    let sparkle = hash12(global_id.xy + vec2<f32>(time * 20.0, 0.0));
    let sparkleBright = smoothstep(0.98, 1.0, sparkle) * treble * totalIntensity * 2.0;
    rgb = rgb + vec3<f32>(sparkleBright);

    let alpha = clamp(totalIntensity + totalTrail * 0.2 + bass * 0.05 + hexData * 0.1, 0.0, 1.0);

    // Premultiplied alpha
    let premultColor = rgb * alpha;
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(premultColor, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
