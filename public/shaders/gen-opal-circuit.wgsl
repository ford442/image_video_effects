// ═══════════════════════════════════════════════════════════════════
//  Opal Circuit
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Bragg play-of-colour from silica-sphere opal domains; Manhattan-routed signal edges with transmission-line ringing
//  A packing: ACES display RGBA in A
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
  config: vec4<f32>,       // x=time, y=rippleCount, zw=resolution
  zoom_config: vec4<f32>,  // x=time, yz=mouse uv, w=mouse down
  zoom_params: vec4<f32>,  // x=Trace Scale, y=Pulse Rate, z=Iridescence, w=Bloom
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

// Native idea 1: opal play-of-colour. Precious opal is a close-packed lattice
// of silica spheres; each ordered domain Bragg-reflects one narrow wavelength
//   lambda = 2 * d * n_eff * cos(theta)
// where d is the sphere-plane spacing, n_eff ~ 1.36 for silica/air, and theta
// the angle between the view ray and the domain's lattice normal. Domains flash
// only near their Bragg alignment, and lambda beyond ~720nm fades to infrared.
fn spectralRGB(lambda: f32) -> vec3<f32> {
  let r = exp(-pow((lambda - 605.0) / 55.0, 2.0)) + 0.25 * exp(-pow((lambda - 430.0) / 25.0, 2.0));
  let g = exp(-pow((lambda - 545.0) / 45.0, 2.0));
  let b = exp(-pow((lambda - 455.0) / 35.0, 2.0));
  let visible = smoothstep(380.0, 410.0, lambda) * (1.0 - smoothstep(690.0, 740.0, lambda));
  return vec3<f32>(r, g, b) * visible;
}

// Returns rgb = diffracted colour, a = domain-boundary mask (1 inside grain).
fn braggPlayOfColour(q: vec2<f32>, viewTilt: vec2<f32>, time: f32, swell: f32) -> vec4<f32> {
  let cell = floor(q);
  let f = fract(q);
  var best = 8.0;
  var second = 8.0;
  var bestId = vec2<f32>(0.0);
  for (var j: i32 = -1; j <= 1; j = j + 1) {
    for (var i: i32 = -1; i <= 1; i = i + 1) {
      let o = vec2<f32>(f32(i), f32(j));
      let site = hash22(cell + o);
      let dv = o + site - f;
      let dd = dot(dv, dv);
      if (dd < best) {
        second = best;
        best = dd;
        bestId = cell + o;
      } else if (dd < second) {
        second = dd;
      }
    }
  }
  let h = hash22(bestId + vec2<f32>(41.3, 7.7));
  let spacing = mix(205.0, 262.0, hash21(bestId + vec2<f32>(3.1, 91.4))) * (1.0 + swell);
  let latticeTilt = (h - 0.5) * 1.1 + vec2<f32>(sin(time * 0.21 + h.x * 6.28), cos(time * 0.17 + h.y * 6.28)) * 0.08;
  let mis = viewTilt - latticeTilt;
  let theta = length(mis);
  let lambda = 2.0 * spacing * 1.36 * cos(min(theta, 1.4));
  let flash = exp(-theta * theta * 7.0);
  let boundary = smoothstep(0.0, 0.08, sqrt(second) - sqrt(best));
  return vec4<f32>(spectralRGB(lambda) * flash, boundary);
}

// Native idea 2: signal propagation on routed copper. Traces are Manhattan
// routed, so an edge launched at a source cell arrives after an L1 path delay.
// Behind the edge the line rings (damped oscillation from impedance mismatch).
fn manhattanEdge(cellDist: f32, front: f32) -> f32 {
  let behind = front - cellDist;
  if (behind < -0.6) { return 0.0; }
  let edge = smoothstep(-0.6, 0.0, behind) * (1.0 - smoothstep(0.0, 0.9, behind));
  let ringing = step(0.0, behind) * exp(-behind * 0.55) * max(cos(behind * 2.6), 0.0) * 0.55;
  return max(edge, ringing);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

  // Bass envelope follower state lives in guarded extraBuffer[133].
  var prevBass = bass;
  if (arrayLength(&extraBuffer) > 138u) {
    prevBass = clamp(extraBuffer[133], 0.0, 1.0);
  }
  let smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
  if (gid.x == 0u && gid.y == 0u) {
    if (arrayLength(&extraBuffer) > 138u) {
      extraBuffer[133] = smoothBass;
    }
  }
  let mouse = u.zoom_config.yz * 2.0 - 1.0;
  let mouseDown = u.zoom_config.w > 0.5;

  let zp_x = u.zoom_params.x; let zp_y = u.zoom_params.y; let zp_z = u.zoom_params.z; let zp_w = u.zoom_params.w; let zp = clamp(vec4<f32>(zp_x, zp_y, zp_z, zp_w), vec4<f32>(0.0), vec4<f32>(1.0));
  let traceScale = mix(5.0, 40.0, zp.x);
  let pulseRate = mix(0.2, 3.0, zp.y);
  let iridescence = mix(0.1, 2.0, zp.z);
  let bloom = mix(0.2, 2.2, zp.w);

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
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

  // Idea 2: click ripples launch Manhattan-routed signal edges; holding the
  // mouse turns the cursor into a clock driver emitting square-wave edges.
  let edgeVelocity = 5.0 + pulseRate * 5.0;
  let gridPos = gc + 0.5;
  var busEdge = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let ripple = u.ripples[i];
    let age = time - ripple.z;
    if (age >= 0.0 && age < 3.0) {
      let rp = ((ripple.xy * 2.0 - 1.0) * aspectVec + mouse * 0.18) * traceScale;
      let dl = abs(gridPos - floor(rp) - 0.5);
      let l1 = dl.x + dl.y;
      busEdge = max(busEdge, manhattanEdge(l1, age * edgeVelocity) * exp(-age * 1.1));
    }
  }
  if (mouseDown) {
    let mp = (mouse * aspectVec + mouse * 0.18) * traceScale;
    let dl = abs(gridPos - floor(mp) - 0.5);
    let l1 = dl.x + dl.y;
    let clockHz = 0.8 + pulseRate * 0.9;
    let clockPhase = fract(time * clockHz - l1 / (edgeVelocity * 2.0));
    let clockHigh = smoothstep(0.0, 0.04, clockPhase) * (1.0 - smoothstep(0.46, 0.5, clockPhase));
    let overshoot = exp(-clockPhase * 18.0) * 0.6;
    busEdge = max(busEdge, (clockHigh * 0.55 + overshoot) * exp(-l1 * 0.06));
  }
  let busGlow = busEdge * traces;

  // Idea 1: Bragg diffraction domains. The viewing angle tilts with the mouse
  // and treble; bass swells the sphere lattice spacing slightly.
  let viewTilt = mouse * vec2<f32>(0.45, 0.35) + vec2<f32>(p.x, p.y) * 0.22 + vec2<f32>(treble * 0.08, 0.0);
  let bragg = braggPlayOfColour(uv * aspectVec * 7.0 + vec2<f32>(3.7, 1.9), viewTilt, time, smoothBass * 0.035);
  let braggFlash = bragg.rgb * bragg.a;

  let opalR = 0.5 + 0.5 * sin(signal * 6.28318 + 0.0 + mids);
  let opalG = 0.5 + 0.5 * sin(signal * 6.28318 + 2.1 + treble + smoothBass * 0.1);
  let opalB = 0.5 + 0.5 * sin(signal * 6.28318 + 4.2 + smoothBass + mids * 0.05);
  let traceOpal = mix(vec3<f32>(opalR * 1.1, opalG, opalB * 0.95), braggFlash * 1.6, clamp(length(braggFlash), 0.0, 1.0) * 0.45);

  let substrate = iridescentSubstrate(uv * 0.7, time, iridescence);

  var color = vec3<f32>(0.02, 0.02, 0.03) + substrate * 0.35;
  color += braggFlash * iridescence * 0.4 * (1.0 - traces * 0.7);
  color += traceOpal * traces * iridescence;
  color += vec3<f32>(0.9, 0.95, 1.0) * vias * bloom * (0.5 + treble);
  color += vec3<f32>(0.2, 0.95, 1.0) * packets * (1.0 + smoothBass) * 1.2;
  color += vec3<f32>(0.6, 0.4, 1.0) * hexEdge * 0.5 * (0.8 + mids * 0.3);
  color += vec3<f32>(1.0, 0.85, 0.45) * busGlow * bloom * (1.1 + bass * 0.4);

  // Exact temporal feedback from C (last frame's display RGBA).
  let prev = textureLoad(dataTextureC, coord, 0);
  color = mix(color, prev.rgb * 0.92, 0.02 + smoothBass * 0.01);

  color = acesToneMap(color * 1.1);

  // Alpha = copper coverage + live signal energy + diffraction flash.
  let alpha = clamp(0.16 + traces * 0.5 + packets * 0.18 + busGlow * 0.3 + length(braggFlash) * 0.12 + hexEdge * 0.05, 0.0, 1.0);
  // Depth: copper traces and vias stand proud of the opal substrate.
  let depth = clamp(0.2 + traces * 0.45 + vias * 0.25, 0.0, 1.0);
  let finalColor = vec4<f32>(color, alpha);

  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
