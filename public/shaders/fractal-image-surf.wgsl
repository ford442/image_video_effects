// ═══════════════════════════════════════════════════════════════════
//  Fractal Image Surf v2
//  Category: distortion
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: fractal-image-surf
//  Upgraded: 2026-10-05
//  Ideas: 1) Burning Ship joins the surf (3-way UV morph, slow drift) 2) escape-lip foam from smooth escape count 3) cardioid walk of Julia c on mids
//  A packing: ACES display RGBA (nothing reads C; HEAD stored det/warp/spec/alpha)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn hash33(p: vec3<f32>) -> vec3<f32> {
  let q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                    dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                    dot(p, vec3<f32>(113.5, 271.9, 124.6)));
  return fract(sin(q) * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// Floor: interpolated value noise (HEAD's fbm was per-pixel white noise,
// which made dwarp a random jitter instead of a domain warp).
fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), s.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x), s.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var val = 0.0;
  var amp = 0.5;
  var freq = 1.0;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    let i2 = vec2<f32>(f32(i) * 37.0, f32(i) * 93.0);
    let n = valueNoise(p * freq + i2);
    val = val + n * amp;
    amp = amp * 0.5;
    freq = freq * 2.03;
  }
  return val;
}

fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

// Idea 2: smooth (fractional) escape count; interior stays at maxIter.
fn smoothEscape(p: vec2<f32>, i: u32) -> f32 {
  let log2Mod = max(0.5 * log2(max(dot(p, p), 1.0001)), 1.0001);
  return max(f32(i) + 1.0 - log2(log2Mod), 0.0);
}

// Helpers return (final z, smooth escape count).
fn julia_iter(z: vec2<f32>, c: vec2<f32>, maxIter: u32) -> vec3<f32> {
  var p = z;
  var n = f32(maxIter);
  for (var i: u32 = 0u; i < maxIter; i = i + 1u) {
    p = cmul(p, p) + c;
    if (dot(p, p) > 16.0) { n = smoothEscape(p, i); break; }
  }
  return vec3<f32>(p, n);
}

fn mandelbrot_iter(z: vec2<f32>, maxIter: u32) -> vec3<f32> {
  var p = vec2<f32>(0.0, 0.0);
  var n = f32(maxIter);
  for (var i: u32 = 0u; i < maxIter; i = i + 1u) {
    p = cmul(p, p) + z;
    if (dot(p, p) > 16.0) { n = smoothEscape(p, i); break; }
  }
  return vec3<f32>(p, n);
}

fn burning_ship_iter(z: vec2<f32>, c: vec2<f32>, maxIter: u32) -> vec3<f32> {
  var p = z;
  var n = f32(maxIter);
  for (var i: u32 = 0u; i < maxIter; i = i + 1u) {
    p = cmul(vec2<f32>(abs(p.x), abs(p.y)), vec2<f32>(abs(p.x), abs(p.y))) + c;
    if (dot(p, p) > 16.0) { n = smoothEscape(p, i); break; }
  }
  return vec3<f32>(p, n);
}

// Escape-lip: escaped late (near the set boundary) but not interior.
fn escapeLip(n: f32, maxIter: u32) -> f32 {
  let s = clamp(n / f32(maxIter), 0.0, 1.0);
  let inside = select(0.0, 1.0, n >= f32(maxIter) - 0.001);
  return smoothstep(0.3, 0.9, s) * (1.0 - inside);
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
  let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
  let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
  let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
  let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r, 0.0, 1.0);

  let iterations = u32(clamp(u.zoom_params.x * 28.0 + 4.0, 4.0, 32.0));
  let zoom = max(u.zoom_params.y * 1.5 + 0.1, 0.1);
  let offset = vec2<f32>(u.zoom_params.z - 0.5, u.zoom_params.w - 0.5) * 0.6;

  let centered = (uv - 0.5) * zoom * (1.0 + bass * 0.3) + offset + (mouse - 0.5) * 0.6;
  let cHead = vec2<f32>((mouse.x - 0.5) * 0.85 + 0.18, (mouse.y - 0.5) * 0.7 - 0.22 + sin(time * 0.9) * 0.07);

  // Idea 3: cardioid walk — mids pull Julia c onto the Mandelbrot main-cardioid
  // boundary c = e^{iθ}/2 − e^{2iθ}/4 (just inside it), so the Julia set stays
  // connected and spiral-rich while mids slide θ along the rim. mids = 0 → HEAD c.
  let theta = -1.25 + (mouse.x - 0.5) * 1.6 + mids * 2.2 + sin(time * 0.13) * 0.5;
  let eiT = vec2<f32>(cos(theta), sin(theta));
  let ei2T = vec2<f32>(cos(2.0 * theta), sin(2.0 * theta));
  let cCard = (eiT * 0.5 - ei2T * 0.25) * 0.985;
  let c = mix(cHead, cCard, smoothstep(0.05, 0.6, mids));

  // Idea 1: slow drift of the morph so Julia → Mandelbrot → Burning Ship shows
  // without audio (0 at t=0, so early frames match HEAD); bass still pushes it.
  let morphDrift = 0.5 - 0.5 * cos(time * 0.045);
  let fractalMorph = clamp(bass + morphDrift, 0.0, 1.0);
  let rJ = julia_iter(centered, c, iterations);
  let rM = mandelbrot_iter(centered, iterations);
  let rB = burning_ship_iter(centered, c, iterations);
  let zJ = rJ.xy;
  let zM = rM.xy;
  let zB = rB.xy;

  let fj = 1.0 / (1.0 + dot(zJ, zJ));
  let fm = 1.0 / (1.0 + dot(zM, zM));
  let fb = 1.0 / (1.0 + dot(zB, zB));
  let w1 = smoothstep(0.0, 0.5, fractalMorph);
  let w2 = smoothstep(0.5, 1.0, fractalMorph);
  let det = fj * (1.0 - w1) + fm * (w1 - w2) + fb * w2;

  // Idea 2: crest height + escape lip, blended with the same morph weights.
  let maxN = f32(iterations);
  let crest = clamp(rJ.z / maxN, 0.0, 1.0) * (1.0 - w1)
            + clamp(rM.z / maxN, 0.0, 1.0) * (w1 - w2)
            + clamp(rB.z / maxN, 0.0, 1.0) * w2;
  let lip = escapeLip(rJ.z, iterations) * (1.0 - w1)
          + escapeLip(rM.z, iterations) * (w1 - w2)
          + escapeLip(rB.z, iterations) * w2;

  let warp = fbm(centered * 3.0 + vec2<f32>(time * 0.1), 5);
  let dwarp = vec2<f32>(
    fbm(centered * 3.0 + vec2<f32>(0.01, 0.0) + vec2<f32>(time * 0.1), 5) - warp,
    fbm(centered * 3.0 + vec2<f32>(0.0, 0.01) + vec2<f32>(time * 0.1), 5) - warp
  ) * 50.0;
  let jac = abs(1.0 + dwarp.x * dwarp.y - dot(dwarp, dwarp) * 0.25);
  let safeJac = max(jac, 0.3);

  let parallax = depth * 0.012;
  let layer1 = uv + (vec2<f32>(zJ.x, zJ.y) * 0.008 + dwarp * 0.005) / safeJac;
  let layer2 = uv + (vec2<f32>(zM.x, zM.y) * 0.006 + dwarp * 0.004) / safeJac + parallax;
  // Idea 1: the Burning Ship z now displaces UV too (HEAD computed zB but only
  // used it in det); weighted by w2 so the third surf layer actually moves the image.
  let layer3 = uv + (vec2<f32>(zB.x, zB.y) * 0.007 + dwarp * 0.0045) / safeJac + parallax * 0.5;
  // Idea 2: wave crest lifts the surf slightly (escape-time height field).
  let crestLift = vec2<f32>(0.0, -0.006) * crest * (1.0 - lip * 0.5);
  let surfUV = layer1 * (1.0 - w1) + layer2 * (w1 - w2) + layer3 * w2 + crestLift;
  let sampleUV = clamp(surfUV, vec2<f32>(0.001), vec2<f32>(0.999));

  let baseColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
  let spec = pow(max(det - 0.4, 0.0), 3.0) * (0.6 + treble * 0.6);
  let hdrSpec = vec3<f32>(0.75, 0.88, 1.0) * spec;

  // Idea 2: escape-lip foam — broken up by the (now smooth) FBM so it reads as
  // spray on the fractal's breaking edge, plus a glint along the lip itself.
  let foam = lip * smoothstep(0.38, 0.62, warp + lip * 0.15);
  let lipGlint = lip * lip * (0.25 + treble * 0.35);
  let foamRGB = vec3<f32>(0.92, 0.97, 1.0) * (foam * 0.55 + lipGlint);

  let grain = hash33(vec3<f32>(uv * resolution, time * 60.0)).x * 0.04 - 0.02;
  let hdr = baseColor.rgb * (0.8 + det * 0.35) + hdrSpec + foamRGB + grain;
  let finalColor = aces_tone_map(max(hdr, vec3<f32>(0.0)));

  // Semantic alpha: source coverage, thickened by fractal density and foam.
  let alpha = clamp(baseColor.a * (0.82 + det * 0.18) + foam * 0.3 + spec * 0.15, 0.0, 1.0);
  let outDepth = clamp(depth + det * 0.05 + warp * 0.03 + crest * 0.04, 0.0, 1.0);

  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
}
