// ═══════════════════════════════════════════════════════════════════
//  Koch Snowflake Storm
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-11-09
//  Ideas: parallax snowfall (3 drifting depth layers sheared by turbulence); rime feathers (6 dendrite ribs with barbs inside each flake, treble-lit); thundersnow flash (bass backlights an fbm cloud deck)
//  Ideas (2026-09-14): Koch self-similar offspring, where each flake buds 1/3-scale copies of itself at its three primary lobes (the Koch generator applied at flake scale, gated by Recursion Depth, pushed out by bass); 22-degree ice halo, a hexagonal-prism refraction ring around every flake with a sharp red inner edge fading to a diffuse blue outer skirt (Chromatic Dispersion + treble)
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Turbulence, y=Recursion Depth, z=Snowflake Count, w=Chromatic Dispersion

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u2 = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
    mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
    u2.y
  );
}

fn fbm(p: vec2<f32>) -> f32 {
  var v = 0.0;
  var a = 0.5;
  var q = p;
  for (var i = 0u; i < 4u; i = i + 1u) {
    v = v + a * noise2(q);
    q = q * 2.03 + vec2<f32>(1.7, 9.2);
    a = a * 0.5;
  }
  return v;
}

fn snowflake_sdf(p: vec2<f32>, size: f32, recurse: i32) -> f32 {
  let a = atan2(p.y, p.x);
  let r = length(p);
  var border = size;
  for (var i = 0; i < recurse; i = i + 1) {
    let fi = f32(i);
    let freq = pow(3.0, fi + 1.0);
    border = border + sin(a * freq + fi * 0.4) * size * 0.18 / pow(3.0, fi);
  }
  return r - border;
}

fn rot2(p: vec2<f32>, a: f32) -> vec2<f32> {
  let c = cos(a);
  let s = sin(a);
  return vec2<f32>(c * p.x - s * p.y, s * p.x + c * p.y);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 22-degree halo: minimum deviation through 60-degree ice prism faces piles
// light into a ring. Red deviates least (sharp inner edge), blue most, and
// the ring skirts off diffusely outward.
fn iceHalo(r: f32, R: f32, width: f32) -> vec3<f32> {
  let x = (r - R) / width;
  let inner = smoothstep(-0.25, 0.0, x);
  let redBand = inner * exp(-max(x, 0.0) * 5.0);
  let greenBand = inner * exp(-pow((x - 0.35) * 2.6, 2.0));
  let blueBand = inner * exp(-max(x - 0.55, 0.0) * 1.6) * smoothstep(0.1, 0.7, x);
  return vec3<f32>(redBand * 1.0, greenBand * 0.75, blueBand * 0.85);
}

// Parallax snowfall: one hashed particle per cell, drifting down.
fn snowLayer(p: vec2<f32>, scale: f32, speed: f32, t: f32, radius: f32) -> f32 {
  let q = p * scale + vec2<f32>(sin(t * 0.3 + p.y) * 0.4, t * speed);
  let cell = floor(q);
  let h = hash21(cell);
  let jit = vec2<f32>(hash21(cell + 7.3), hash21(cell + 3.1)) * 0.7 + 0.15;
  let d = length(fract(q) - jit);
  return smoothstep(radius, radius * 0.3, d) * step(0.45, h);
}

// Rime feathers: 6 thin ribs with side barbs inside a flake body.
fn rimeFeathers(local: vec2<f32>, size: f32) -> f32 {
  let a = atan2(local.y, local.x);
  let r = length(local) / size;
  let sector = (fract(a / 1.0472 + 0.5) - 0.5) * 1.0472; // angle from nearest rib
  let ribD = abs(sin(sector)) * r;
  let rib = smoothstep(0.035, 0.0, ribD);
  let barb = smoothstep(0.05, 0.0, abs(fract(r * 6.0 - ribD * 5.0) - 0.5) * 0.25) * smoothstep(0.18, 0.0, ribD);
  return (rib + barb * 0.5) * smoothstep(1.0, 0.2, r);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let coord = vec2<i32>(gid.xy);
  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let time = u.config.x;
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let mouse = u.zoom_config.yz;
  let mouseHeld = step(0.5, u.zoom_config.w);

  let turbStrength = mix(0.05, 0.45, clamp(u.zoom_params.x + bass * 0.35, 0.0, 1.0));
  let recursionF = mix(2.0, 5.0, u.zoom_params.y);
  let recursions = i32(recursionF);
  let snowCount = i32(mix(2.0, 5.0, u.zoom_params.z));
  let dispersion = u.zoom_params.w;

  let aspect = f32(dims.x) / max(f32(dims.y), 1.0);
  var p = (uv - 0.5) * vec2<f32>(aspect, 1.0) * 3.0;

  let mousePos = (mouse - 0.5) * vec2<f32>(aspect, 1.0) * 2.0;
  let warp = fbm(p * 2.5 + vec2<f32>(time * 0.18, time * 0.12)) * turbStrength;
  p = p + vec2<f32>(cos(warp * 6.283), sin(warp * 6.283)) * turbStrength * 0.25;

  // Click ripples: gust fronts that blow the storm outward and spin flakes.
  var gustSpin = 0.0;
  var gustLight = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (age >= 0.0 && age < 2.5) {
      let rpos = (rp.xy - 0.5) * vec2<f32>(aspect, 1.0) * 3.0;
      let dv = p - rpos;
      let dl = max(length(dv), 1e-4);
      let front = dl - age * 1.6;
      let env = exp(-front * front * 6.0) * exp(-age * 1.4);
      p = p - (dv / dl) * env * 0.12;
      gustSpin += env * 1.5;
      gustLight += env;
    }
  }

  var minDist = 1e9;
  var nearestSize = 0.0;
  var rime = 0.0;
  var halo = vec3<f32>(0.0);

  // Offspring fade in as Recursion Depth rises past its first step.
  let offspringAmt = smoothstep(2.6, 3.4, recursionF);
  let childRecurse = max(recursions - 1, 1);
  let mouseAttract = 0.4 + 0.35 * mouseHeld;

  for (var si = 0; si < snowCount; si = si + 1) {
    let sf = f32(si);
    let angle = sf * 2.094 + time * 0.08 * (1.0 + bass * 0.5);
    let dist = 0.7 + sin(sf * 1.3 + time * 0.15) * 0.35;
    let offset = vec2<f32>(cos(angle), sin(angle)) * dist + mousePos * mouseAttract;
    let size = 0.25 + sin(sf * 2.7) * 0.12;
    // Flutter: flakes rock as they tumble through the storm (mids = gustier).
    let spin = sin(time * 0.6 + sf * 1.7) * 0.35 * (1.0 + mids * 0.6) + gustSpin;
    let local = rot2(p - offset, spin);
    let d = snowflake_sdf(local, size, recursions);
    if (d < minDist) {
      minDist = d;
      nearestSize = size;
    }
    rime = max(rime, rimeFeathers(local, size) * smoothstep(0.0, 0.03, -d));

    // ── Idea 1: Koch self-similar offspring at the three primary lobes ──
    if (offspringAmt > 0.001) {
      let childSize = size / 3.0;
      let tipR = size * 1.18 + childSize * (0.9 + bass * 0.7);
      for (var k = 0; k < 3; k = k + 1) {
        let lobeA = 0.5236 + f32(k) * 2.0944; // sin(3a)=1 at pi/6 + k*2pi/3
        let cpos = vec2<f32>(cos(lobeA), sin(lobeA)) * tipR;
        let cl = rot2(local - cpos, -spin * 2.0 + time * 0.3);
        let cd = snowflake_sdf(cl, childSize * offspringAmt, childRecurse);
        if (cd < minDist) {
          minDist = cd;
          nearestSize = childSize * max(offspringAmt, 0.2);
        }
      }
    }

    // ── Idea 2: 22-degree ice halo around each flake ──
    let haloR = size * 2.4;
    halo += iceHalo(length(p - offset), haloR, size * 0.55) * (0.08 + dispersion * 0.35) * (1.0 + treble * 1.2);
  }

  let edge = abs(minDist) / nearestSize;
  let inside = smoothstep(0.0, 0.08, -minDist);
  let glow = exp(-edge * 4.0);

  // Storm sky (rescue: HEAD painted pale ice everywhere → ACES white wash).
  let skyUV = (uv - 0.5) * vec2<f32>(aspect, 1.0);
  var sky = mix(vec3<f32>(0.035, 0.05, 0.09), vec3<f32>(0.01, 0.015, 0.035), uv.y);
  // Thundersnow flash: bass backlights an fbm cloud deck.
  let cloud = fbm(skyUV * 3.0 + vec2<f32>(time * 0.05, 0.0));
  let flash = smoothstep(0.55, 0.95, bass) * (0.6 + 0.4 * sin(time * 37.0));
  sky += vec3<f32>(0.08, 0.1, 0.16) * cloud * (0.35 + flash * 3.5);
  // Parallax snowfall: far → near, larger and softer, sheared by turbulence.
  let shear = vec2<f32>(warp * 0.6, 0.0);
  let snow = snowLayer(skyUV + shear * 0.3, 22.0, 0.9, time, 0.08) * 0.35
           + snowLayer(skyUV + shear * 0.6, 12.0, 0.6, time, 0.1) * 0.55
           + snowLayer(skyUV + shear, 6.0, 0.4, time, 0.14) * 0.8;
  sky += vec3<f32>(0.75, 0.85, 1.0) * snow * (1.0 + flash);

  var color = mix(
    sky,
    vec3<f32>(0.12, 0.35, 0.55),
    inside
  );
  color += vec3<f32>(0.7, 0.9, 1.0) * rime * (0.35 + treble * 0.8);

  color = color + vec3<f32>(0.6, 0.75, 1.0) * glow * 1.5 * (1.0 + treble * 0.4);

  let ca = smoothstep(0.1, 0.5, edge) * dispersion;
  color = vec3<f32>(
    color.r * (1.0 + ca * 0.15),
    color.g * (1.0 + ca * 0.05),
    color.b * (1.0 - ca * 0.08)
  );

  color = color + halo + vec3<f32>(0.5, 0.7, 1.0) * gustLight * 0.3;

  // Single ACES pass on the display colour.
  let display = aces(color * 1.8);

  // Alpha: ice coverage (crystal body + edge glow) plus halo light.
  let haloLuma = dot(halo, vec3<f32>(0.3, 0.5, 0.2));
  let alpha = clamp(inside * 0.85 + glow * 0.6 + haloLuma * 0.8 + gustLight * 0.2, 0.02, 1.0);
  let depth = clamp(1.0 - edge * 0.8, 0.0, 1.0);

  let finalColor = vec4<f32>(display, alpha);
  textureStore(writeTexture, coord, finalColor);
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, finalColor);
}
