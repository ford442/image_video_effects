// ═══════════════════════════════════════════════════════════════════
//  Opal Circuit
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, hex-grid,
//            data-packets, iridescent-substrate
//  Complexity: High
//  Created: 2026-05-31
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn sat(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.1, 29.6)));
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var value = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    value += amplitude * noise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
  let k = select(release, attack, bass > prev);
  return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hexDistance(uv: vec2<f32>, scale: f32) -> f32 {
  let q = sqrt(3.0);
  let h = uv * scale;
  let ax = vec2<f32>(q * 0.5, 0.5);
  let ay = vec2<f32>(0.0, 1.0);
  let cx = dot(h, ax);
  let cy = dot(h, ay - ax * 0.5);
  let rx = round(cx);
  let ry = round(cy);
  let rz = round(-cx - cy);
  let dx = abs(cx - rx);
  let dy = abs(cy - ry);
  let dz = abs(-cx - cy - rz);
  return max(max(dx, dy), dz);
}

fn iridescentSubstrate(uv: vec2<f32>, time: f32, strength: f32) -> vec3<f32> {
  let n = fbm(uv * 5.0 + time * 0.1, 4);
  let angle = n * 6.28318;
  let r = 0.5 + 0.5 * cos(angle + 0.0);
  let g = 0.5 + 0.5 * cos(angle + 2.1);
  let b = 0.5 + 0.5 * cos(angle + 4.2);
  return vec3<f32>(r, g, b) * strength;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  let prevBass = extraBuffer[0];
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  if (gid.x == 0u && gid.y == 0u) {
    extraBuffer[0] = smoothBass;
  }
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz * 2.0 - 1.0;

  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let traceScale = mix(5.0, 40.0, zp.x);
  let pulseRate = mix(0.2, 3.0, zp.y);
  let iridescence = mix(0.1, 2.0, zp.z);
  let bloom = mix(0.2, 2.2, zp.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = uv * 2.0 - 1.0;
  p.x = p.x * aspect;
  p = p + mouse * 0.18;

  let hexDist = hexDistance(uv + mouse * 0.05, traceScale * 0.5);
  let hexEdge = smoothstep(0.52, 0.48, hexDist) * (1.0 - smoothstep(0.48, 0.44, hexDist));

  let g = p * traceScale;
  let gc = floor(g);
  let gl = fract(g) - 0.5;
  let rnd = hash21(gc);

  let hLine = smoothstep(0.09, 0.01, abs(gl.y)) * step(0.35, rnd);
  let vLine = smoothstep(0.09, 0.01, abs(gl.x)) * step(rnd, 0.65);
  let vias = exp(-dot(gl, gl) * 60.0) * step(0.7, rnd);
  let traces = max(max(hLine, vLine), vias);

  let signal = 0.5 + 0.5 * sin(time * pulseRate * (1.0 + smoothBass * 0.8) + (gc.x + gc.y) * 0.7);

  var packets = 0.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let fi = f32(i);
    let seed = hash22(gc + fi * 3.7);
    let axis = step(seed.x, 0.5);
    let cellLocal = select(gl.x, gl.y, axis < 0.5);
    let offset = hash21(gc + fi * 13.1);
    let speed = 0.15 + hash21(gc + fi * 7.9) * 0.35;
    let packetPos = fract(time * speed + offset);
    let d = abs(cellLocal - (packetPos - 0.5));
    packets += smoothstep(0.06, 0.0, d) * step(0.6, rnd + fi * 0.05);
  }
  packets = sat(packets);

  let opalR = 0.5 + 0.5 * sin(signal * 6.28318 + 0.0 + mids);
  let opalG = 0.5 + 0.5 * sin(signal * 6.28318 + 2.1 + treble + smoothBass * 0.1);
  let opalB = 0.5 + 0.5 * sin(signal * 6.28318 + 4.2 + smoothBass + mids * 0.05);

  let substrate = iridescentSubstrate(uv * 0.7, time, iridescence);

  var color = vec3<f32>(0.02, 0.02, 0.03) + substrate * 0.35;
  color += vec3<f32>(opalR * 1.1, opalG, opalB * 0.95) * traces * iridescence;
  color += vec3<f32>(0.9, 0.95, 1.0) * vias * bloom * (0.5 + treble);
  color += vec3<f32>(0.2, 0.95, 1.0) * packets * (1.0 + smoothBass) * 1.2;
  color += vec3<f32>(0.6, 0.4, 1.0) * hexEdge * 0.5 * (0.8 + mids * 0.3);

  let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
  color = mix(color, prev.rgb * 0.92, 0.02 + smoothBass * 0.01);

  color = acesToneMap(color * 1.1);

  textureStore(writeTexture, coord, vec4<f32>(color, 1.0));
  textureStore(writeDepthTexture, coord, vec4<f32>(0.0, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(traces, signal, packets, hexEdge));
}
