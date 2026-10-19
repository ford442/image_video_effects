// ═══════════════════════════════════════════════════════════════════
//  Bioreactor Bloom
//  Category: generative
//  Features: procedural, audio-reactive, mouse-driven, temporal, chromatic,
//            upgraded-rgba, depth-aware, aces-tone-map, cell-sdf,
//            nutrient-tendrils, pulsing-bloom, fbm-warp
//  Complexity: High
//  Created: 2026-05-31
//  Upgraded: 2026-09-27, 2026-10-19
//  Ideas: mitosis split event budding a second nucleus along a hashed
//         division axis; toxicity necrosis creep fading tendrils that
//         overlap the poison cloud; reactivity-scaled bloom-ring
//         speed/thickness; cleavage furrow + dumbbell membrane during
//         division; quorum-sensing pulse lock from the 3x3 neighbourhood
//  A packing: display RGBA (fixed — previously wrote raw fields while C was
//             read as color; now matches the C-read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

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

fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
  return length(p) - r;
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let pa = p - a;
  let ba = b - a;
  let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

fn nutrientTendril(uv: vec2<f32>, time: f32, cell: vec2<f32>, seed: vec2<f32>, lengthScale: f32) -> f32 {
  var d = 1e3;
  let segments = 6;
  var prev = cell + (seed - 0.5) * 0.6;
  for (var i: i32 = 1; i <= segments; i = i + 1) {
    let fi = f32(i);
    let wave = vec2<f32>(
      sin(time * 0.7 + seed.x * 5.0 + fi * 0.9),
      cos(time * 0.6 + seed.y * 5.0 + fi * 0.7)
    );
    let next = cell + (seed - 0.5) * 0.6 + wave * 0.25 * lengthScale + vec2<f32>(fi * 0.08, sin(fi + time) * 0.05);
    d = min(d, sdSegment(uv, prev, next));
    prev = next;
  }
  return smoothstep(0.03, 0.0, d);
}

fn pulseBloom(uv: vec2<f32>, time: f32, center: vec2<f32>, radius: f32, speed: f32, sharpness: f32) -> f32 {
  let d = length(uv - center);
  let ring = abs(d - radius * (0.7 + 0.3 * sin(time * speed)));
  return exp(-ring * ring * sharpness) * smoothstep(radius * 1.5, 0.0, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let dims = vec2<u32>(u32(u.config.z), u32(u.config.w));
  if (gid.x >= dims.x || gid.y >= dims.y) { return; }

  let uv = (vec2<f32>(gid.xy) + 0.5) / vec2<f32>(dims);
  let coord = vec2<i32>(gid.xy);
  let time = u.config.x;
  let bass = plasmaBuffer[0].x;

  // Smoothed bass envelope (relocated from extraBuffer[0] to guarded slot 133,
  // single writer at (0,0)).
  var smoothBass = bass;
  if (arrayLength(&extraBuffer) > 138u) {
    let prevBass = extraBuffer[133];
    smoothBass = bass_env(prevBass, bass, 0.8, 0.15);
    if (gid.x == 0u && gid.y == 0u) {
      extraBuffer[133] = smoothBass;
    }
  }
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;
  let mouse = u.zoom_config.yz;

  let zp = clamp(u.zoom_params, vec4<f32>(0.0), vec4<f32>(1.0));

  let cellScale = mix(6.0, 52.0, zp.x);
  let mitosis = mix(0.0, 1.0, zp.y);
  let reactivity = mix(0.2, 2.2, zp.z);
  let toxicity = mix(0.0, 1.0, zp.w);

  let warpedUV = uv + vec2<f32>(
    fbm(uv * 2.0 + vec2<f32>(time * 0.05, 0.0), 3) - 0.5,
    fbm(uv * 2.0 + vec2<f32>(0.0, time * 0.04), 3) - 0.5
  ) * 0.03 * (1.0 + mids);

  let gridUV = warpedUV * cellScale + vec2<f32>(time * (0.08 + smoothBass * 0.18), -time * 0.06);
  let cell = floor(gridUV);
  let local = fract(gridUV) - 0.5;
  let seed = hash22(cell);
  let center = (seed - 0.5) * (0.7 + mitosis * 0.5);

  let d = length(local - center);
  let nucleus = exp(-d * d * (18.0 + reactivity * 22.0));

  // ── Idea 5: quorum-sensing pulse lock ──
  // Each cell reads its 3x3 neighbourhood's seeds. Bigger cells (seed.x)
  // secrete more autoinducer; past a Reactivity-scaled threshold the cell's
  // pulse phase is pulled toward the neighbourhood phase, so dense patches of
  // the culture blink in sync (V. fischeri-style quorum luminescence).
  var nbSeedSum = vec2<f32>(0.0);
  for (var oy: i32 = -1; oy <= 1; oy = oy + 1) {
    for (var ox: i32 = -1; ox <= 1; ox = ox + 1) {
      nbSeedSum += hash22(cell + vec2<f32>(f32(ox), f32(oy)));
    }
  }
  let nbMean = nbSeedSum / 9.0;
  let autoinducer = nbMean.x * (0.6 + reactivity * 0.35);
  let quorumLock = smoothstep(0.52, 0.66, autoinducer);
  let pulsePhase = mix(seed.y, nbMean.y, quorumLock) * 9.0;
  let pulse = 0.5 + 0.5 * sin(time * (2.5 + mids * 6.0) + pulsePhase + d * 18.0);

  // Mitosis split event: past a phase+mitosis threshold, a second nucleus
  // buds off along a hashed division axis, so the Mitosis slider shows real
  // cell division instead of only biasing the base offset.
  let divisionAxis = normalize(seed - 0.5 + vec2<f32>(0.0001));
  let mitosisPhase = fract(time * (0.15 + mitosis * 0.25) + seed.x * 4.0);
  let dividing = smoothstep(0.55, 0.95, mitosis) * smoothstep(0.35, 0.65, mitosisPhase) * smoothstep(1.0, 0.8, mitosisPhase);
  let center2 = center + divisionAxis * dividing * 0.34;
  let d2 = length(local - center2);
  let nucleus2 = exp(-d2 * d2 * (18.0 + reactivity * 22.0)) * dividing;
  let nucleusTotal = sat(nucleus + nucleus2);

  // ── Idea 4: cleavage furrow ──
  // During division the membrane wraps both nuclei (dumbbell union of the
  // parent and bud circles) and a contractile ring pinches the cytoplasm on
  // the plane perpendicular to the division axis at the parent/bud midpoint.
  // With dividing == 0 the bud circle is pushed far away, so the membrane is
  // exactly the original single circle.
  let membraneR = 0.22 + seed.x * 0.18;
  let sdParent = sdCircle(local - center, membraneR);
  let sdBud = sdCircle(local - center2, membraneR * 0.8) + (1.0 - dividing) * 2.0;
  let sdCellBody = min(sdParent, sdBud);
  let membrane = smoothstep(0.25, 0.05, abs(sdCellBody));
  let midPt = (center + center2) * 0.5;
  let furrowS = dot(local - midPt, divisionAxis);
  let furrowT = dot(local - midPt, vec2<f32>(-divisionAxis.y, divisionAxis.x));
  let pinchR = membraneR * (1.0 - 0.65 * dividing);
  let cytoplasm = smoothstep(0.02, -0.04, sdCellBody);
  let furrowLine = exp(-furrowS * furrowS * 900.0) * cytoplasm * dividing;
  let contractileRing = exp(-furrowS * furrowS * 900.0)
    * exp(-(abs(furrowT) - pinchR) * (abs(furrowT) - pinchR) * 700.0) * dividing;

  let colony = (nucleusTotal * (0.7 + pulse * 0.7) + membrane * 0.5) * (1.0 - 0.55 * furrowLine);

  var tendrils = 0.0;
  for (var i: i32 = 0; i < 3; i = i + 1) {
    let fi = f32(i);
    let tseed = hash22(cell + fi * 31.7);
    let tcell = local + (tseed - 0.5) * 0.5;
    tendrils += nutrientTendril(local, time + fi, cell, tseed, 1.0 + smoothBass);
  }
  tendrils = sat(tendrils) * (0.6 + reactivity * 0.5);

  // Reactivity-scaled bloom pulse: ring speed AND thickness now respond to
  // bass x Reactivity, which previously never touched the bloom rings.
  let bloomSharpness = mix(40.0, 110.0, reactivity);
  var bloomLayers = 0.0;
  for (var i: i32 = 0; i < 2; i = i + 1) {
    let fi = f32(i);
    let bloomCenter = uv + (hash22(cell + fi * 17.3) - 0.5) * 0.4;
    let bloomSpeed = (0.8 + hash21(cell + fi * 9.1) * 1.5) * (1.0 + smoothBass * reactivity * 0.6);
    bloomLayers += pulseBloom(uv, time, bloomCenter, 0.12 + fi * 0.08, bloomSpeed, bloomSharpness);
  }
  bloomLayers = sat(bloomLayers) * (0.5 + mids * 0.5) * (0.6 + reactivity * 0.5);

  let poisonCloud = exp(-length(uv - mouse) * (4.0 + toxicity * 12.0)) * toxicity;
  let spores = step(0.994 - treble * 0.03, hash21(floor((warpedUV + time * 0.03) * 300.0)));

  // Toxicity necrosis creep: tendrils overlapping the poison cloud fade
  // toward a necrotic tone and lose brightness, coupling the two previously
  // independent additive layers.
  let necrosis = sat(tendrils * poisonCloud * 3.0);
  let tendrilColor = mix(vec3<f32>(0.3, 0.9, 1.0), vec3<f32>(0.35, 0.22, 0.12), necrosis);
  let tendrilBrightness = tendrils * 0.8 * (1.0 + treble * 0.2) * mix(1.0, 0.4, necrosis);

  // Exact previous-frame state — no filtering
  let prev = textureLoad(dataTextureC, coord, 0);

  var color = vec3<f32>(0.02, 0.05, 0.03);
  color += vec3<f32>(0.1, 0.95, 0.5) * colony * (0.6 + reactivity * 0.7) * (1.0 + smoothBass * 0.1);
  color += vec3<f32>(0.5, 1.0, 0.85) * nucleusTotal * pulse * 0.6 * (1.0 + mids * 0.1);
  color += tendrilColor * tendrilBrightness;
  color += vec3<f32>(0.2, 0.85, 0.4) * bloomLayers * 0.7 * (1.0 + smoothBass * 0.15);
  color += vec3<f32>(0.65, 0.05, 0.15) * poisonCloud * (1.0 + treble * 0.15);
  color += vec3<f32>(0.9, 1.0, 0.75) * spores * (0.3 + treble);
  // Idea 4 (cont.): the actomyosin ring glows where it cinches the membrane.
  color += vec3<f32>(0.85, 1.0, 0.6) * contractileRing * 0.6;
  // Idea 5 (cont.): quorum-locked cells share a synchronous luminescent wash.
  color += vec3<f32>(0.35, 1.0, 0.75) * quorumLock * (0.4 + 0.6 * pulse) * cytoplasm * 0.22;

  color = mix(color, prev.rgb * 0.9, 0.03 + smoothBass * 0.01);

  color = acesToneMap(max(color * 1.1, vec3<f32>(0.0)));

  // Semantic alpha: colony/tendril/bloom/toxin coverage, not a flat literal
  let alpha = clamp(
    0.12 + sat(nucleusTotal + membrane) * 0.5 + tendrils * 0.3 + bloomLayers * 0.25
      + poisonCloud * 0.4 + spores * 0.3 + contractileRing * 0.2,
    0.0, 1.0);

  // Truthful relief from the colony/bloom height field (no raymarch here)
  let relief = sat(nucleusTotal * 0.6 + membrane * 0.4 + bloomLayers * 0.2);
  let depthVal = clamp(1.0 - relief * 0.8, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
  // A packing fixed to display RGBA to match how this shader reads C as color.
  textureStore(dataTextureA, coord, vec4<f32>(color, alpha));
}
