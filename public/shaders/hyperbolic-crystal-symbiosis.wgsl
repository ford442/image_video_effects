// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Crystal Symbiosis v6 — Strict Constraints
//  Upgraded: 2026-11-10
//  Ideas: (1) hyperbolic echo — a Poincaré-style r/(1-r²) remap repeats the
//         crystal cluster in shrinking tiers toward the rim; (2) cut-gem
//         facets — angular quantisation around each blob gives flat facet
//         normals with a moving key light and sparkle; (3) click fronts
//         now read real ripples (old loop gated on ripples.w, always 0).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
  let c = uv - vec2<f32>(0.5);
  let a = atan2(c.y, c.x);
  let r = length(c);
  let seg = TAU / max(segs, 1.0);
  let m = fract((a + seg * 0.5) / seg) * seg;
  let a2 = abs(m - seg * 0.5);
  return vec2<f32>(0.5) + r * vec2<f32>(cos(a2), sin(a2));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let pixel = vec2<i32>(gid.xy);
  let res = vec2<f32>(u.config.zw);
  if (f32(pixel.x) >= res.x || f32(pixel.y) >= res.y) { return; }

  let uv = vec2<f32>(pixel) / res;
  let time = u.config.x;
  
  // Truthful three-band audio
  let bass = plasmaBuffer[0].x;
  let mid = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let bins = plasmaBuffer[1]; // extra bins if needed

  let mouse = u.zoom_config.yz; 
  let mouseDown = u.zoom_config.w;

  let p1 = u.zoom_params.x; 
  let p2 = u.zoom_params.y; 
  let p3 = u.zoom_params.z; 
  let p4 = u.zoom_params.w;

  // Persistent state in extraBuffer[133..138] (single writer)
  if (gid.x == 0u && gid.y == 0u) {
    let dt = 0.016;
    
    // Bounded spring for bass
    let prev_val = extraBuffer[133];
    let prev_vel = extraBuffer[134];
    let force = 100.0 * (bass - prev_val) - 10.0 * prev_vel;
    let next_vel = clamp(prev_vel + force * dt, -10.0, 10.0);
    let next_val = clamp(prev_val + next_vel * dt, 0.0, 1.0);
    extraBuffer[133] = next_val;
    extraBuffer[134] = next_vel;
    
    // Held-pointer response
    let prev_held = extraBuffer[135];
    extraBuffer[135] = mix(prev_held, mouseDown, 0.1);
  }
  
  let springBass = extraBuffer[133];
  let heldPointer = extraBuffer[135];

  // Exact textureLoad (no filtering)
  let prevColor = textureLoad(dataTextureC, pixel, 0).rgb;

  // Continuous geometry
  let segs = max(3.0, floor(p2 * 8.0 + springBass * 4.0));
  let kuv = kaleido(uv, segs);
  
  let d1 = length(kuv - vec2<f32>(0.3, 0.3 + heldPointer * 0.1));
  let d2 = length(kuv - vec2<f32>(0.7, 0.4 - springBass * 0.1));
  let d3 = length(kuv - vec2<f32>(0.5, 0.7));
  
  var d = smin(smin(d1, d2, 0.2), d3, 0.2 + p1 * 0.3);

  // Idea 1: hyperbolic echo tier — compress radius toward the disk rim.
  let hc = uv - vec2<f32>(0.5);
  let hr = length(hc);
  let hr2 = clamp(hr * 1.8, 0.0, 0.97);
  let hyp = hr2 / max(1.0 - hr2 * hr2, 0.03);
  let huv = vec2<f32>(0.5) + normalize(hc + vec2<f32>(1e-5)) * fract(hyp * 0.5) * 0.5;
  let kuv2 = kaleido(huv, segs);
  let dh = min(min(length(kuv2 - vec2<f32>(0.3, 0.3)), length(kuv2 - vec2<f32>(0.7, 0.4))), length(kuv2 - vec2<f32>(0.5, 0.7)));
  let tierFade = smoothstep(0.15, 0.45, hr);
  d = smin(d, dh + 0.03, 0.12 * tierFade + 0.001) * tierFade + d * (1.0 - tierFade);
  let geometryEdge = smoothstep(0.1, 0.08, d);

  // Capped click fronts
  var clickFronts = 0.0;
  let rippleCount = min(u32(u.config.y), 10u);
  for (var i = 0u; i < rippleCount; i++) {
    let r = u.ripples[i];
    let age = time - r.z;
    if (age > 0.0 && age < 3.0) {
      let dist = length(uv - r.xy);
      let wave = sin(max(0.0, age * 15.0 - dist * 40.0));
      clickFronts += wave * exp(-age * 2.0);
    }
  }
  clickFronts = clamp(clickFronts, -1.0, 1.0); // Capped
  
  let phase = time * 0.5 + d * 5.0 + clickFronts;
  let color1 = vec3<f32>(0.5 + 0.5 * cos(phase + vec3<f32>(0.0, 2.0, 4.0)));
  let color2 = vec3<f32>(0.5 + 0.5 * sin(phase + vec3<f32>(1.0, 3.0, 5.0)));
  
  var rawColor = mix(color1, color2, geometryEdge);

  // Idea 2: cut-gem facets — quantised angle around the nearest blob centre.
  var cdir = kuv - vec2<f32>(0.3, 0.3 + heldPointer * 0.1);
  if (d2 < d1 && d2 < d3) { cdir = kuv - vec2<f32>(0.7, 0.4 - springBass * 0.1); }
  if (d3 < d1 && d3 < d2) { cdir = kuv - vec2<f32>(0.5, 0.7); }
  let facetCount = 5.0 + floor(p3 * 7.0);
  let fa = (floor(atan2(cdir.y, cdir.x) / TAU * facetCount) + 0.5) / facetCount * TAU;
  let facetN = normalize(vec3<f32>(cos(fa), sin(fa), 1.2));
  let keyL = normalize(vec3<f32>(cos(time * 0.4), sin(time * 0.4), 1.0));
  let facetLit = max(dot(facetN, keyL), 0.0);
  let sparkle = pow(facetLit, 24.0) * (1.0 + treble * 2.0);
  rawColor *= mix(1.0, 0.55 + facetLit * 0.7, geometryEdge);
  rawColor += vec3<f32>(sparkle) * geometryEdge * 0.6;
  
  // Mix audio bands visually
  rawColor += vec3<f32>(bass, mid, treble) * 0.2 * clickFronts;
  
  // Optical / prismatic feedback mix
  let offset = vec2<i32>(i32(cos(time)*2.0), i32(sin(time)*2.0));
  let prevColorShift = textureLoad(dataTextureC, clamp(pixel + offset, vec2<i32>(0), vec2<i32>(res)-1), 0).rgb;
  
  rawColor = mix(rawColor, prevColorShift, 0.85 + p4 * 0.1);
  
  // Apply ACES Tone Map
  let finalColor = acesToneMap(rawColor);
  
  // Semantic alpha
  let alpha = clamp(geometryEdge + abs(clickFronts) + heldPointer * 0.5 + p3, 0.0, 1.0);
  
  let displayRGBA = vec4<f32>(finalColor, alpha);

  // Write final display RGBA ONLY to dataTextureA (and writeTexture)
  textureStore(dataTextureA, pixel, displayRGBA);
  textureStore(writeTexture, pixel, displayRGBA);
  
  // Depth texture write
  textureStore(writeDepthTexture, pixel, vec4<f32>(d, 0.0, 0.0, 0.0));
}
