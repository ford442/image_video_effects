// ═══════════════════════════════════════════════════════════════════
//  Plasma Ball
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-16
//  Ideas: arc filaments between orbs; luma corona on the photo
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const BALL_COUNT: u32 = 8u;

// Simple Hash for Noise
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var p2 = p;
    // Rotate to reduce axial bias
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (var i = 0; i < 3; i = i + 1) {
        v += a * noise(p2);
        p2 = rot * p2 * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
    return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let uv = vec2<f32>(global_id.xy) / resolution;

  // Evaluate UI params
  let orb_eval = u.zoom_params.x;
  let orbit_eval = u.zoom_params.y;
  let int_eval = u.zoom_params.z;
  let shadow_eval = u.zoom_params.w;

  // Sample original image
  let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

  let audioBass = plasmaBuffer[0].x;
  let audioMid = plasmaBuffer[0].y;
  let audioHigh = plasmaBuffer[0].z;
  let audioReactivity = 1.0 + (audioBass + audioMid + audioHigh) * 0.17;

  // Plasma Calculation
  var plasmaField = 0.0;
  var plasmaColor = vec3<f32>(0.0);
  var shadowVal = 0.0;

  let time = u.config.x;
  let aspect = resolution.x / resolution.y;

  // Iterate procedural plasma balls. The cluster orbits the pointer.
  var orbPos: array<vec2<f32>, 8>;
  var orbCol: array<vec3<f32>, 8>;
  let origin = mix(vec2<f32>(0.5), clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0)), 0.72);
  for (var i = 0u; i < BALL_COUNT; i = i + 1u) {
      let fi = f32(i);
      // Procedural orbital motion
      let angle = time * (0.1 + u.zoom_params.y * 0.4) + fi * 0.785398;
      let radiusOrbit = (0.25 + 0.12 * sin(time * 0.17 + fi * 0.63)) * (0.5 + u.zoom_params.x);
      var pos = origin + vec2<f32>(radiusOrbit * cos(angle), radiusOrbit * sin(angle) * 0.6);
      orbPos[i] = pos;
      // Audio reactive pulse
      let radius = (0.045 + 0.025 * sin(time * 1.5 + fi) + 0.015 * audioBass) * (0.5 + u.zoom_params.x * 0.5);
      let ballColor = hsv2rgb(fract(0.12 * fi + time * 0.05), 0.85, 1.0);
      orbCol[i] = ballColor;

      if (radius > 0.0) {
          // Correct aspect ratio for distance
          let dvec = (uv - pos) * vec2<f32>(aspect, 1.0);
          let dist = length(dvec);

          // Velocity-derived trail direction
          let nextPos = origin + vec2<f32>(
              radiusOrbit * cos(angle + 0.01),
              radiusOrbit * sin(angle + 0.01) * 0.6
          );
          let vel = nextPos - pos;
          let velDir = normalize(vel + vec2<f32>(0.0001));

          // Wisp/Noise distortion
          let noiseVal = fbm(uv * 20.0 - vel * time * 8.0 * audioReactivity + vec2<f32>(fi * 12.34));

          // Trail behind velocity
          let dotP = dot(normalize(dvec), velDir);
          let trail = smoothstep(0.2, 1.0, -dotP);

          // Irregular whooshing
          let distortion = 1.0 + (1.5 * noiseVal * trail) + (0.5 * noiseVal);
          let effectiveRadius = radius * distortion;

          // Metaball influence
          let influence = exp(-40.0 * (dist * dist) / (effectiveRadius * effectiveRadius));

          plasmaField += influence;
          plasmaColor += ballColor * influence * 1.5;

          // Shadow logic
          let shadowOffset = vec2<f32>(0.01, 0.01);
          let shadowUV = uv - shadowOffset;
          let dvecShadow = (shadowUV - pos) * vec2<f32>(aspect, 1.0);
          let distShadow = length(dvecShadow);
          let shadowInfluence = exp(-100.0 * (distShadow * distShadow) / (radius * radius));
          shadowVal += shadowInfluence;
      }
  }

  // Resolve Plasma
  var finalColor = baseColor.rgb;

  // Apply Shadow first (on the image)
  let shadowStr = smoothstep(0.1, 1.0, shadowVal);
  finalColor = mix(finalColor, finalColor * 0.5, shadowStr * u.zoom_params.w);

  // Render Plasma on top
  if (plasmaField > 0.1) {
      // Normalize color
      let renderColor = plasmaColor / plasmaField;

      // Add core glow
      let core = smoothstep(0.8, 2.0, plasmaField);

      let wispColor = renderColor;
      let coreColor = vec3<f32>(1.0, 1.0, 1.0);

      let plasmaFinal = mix(wispColor, coreColor, core);

      let alpha = clamp(plasmaField, 0.0, 1.0);
      finalColor = mix(finalColor, plasmaFinal, alpha * u.zoom_params.z);
  }

  // Idea 1 — arc filaments between consecutive orbs.
  var filament = 0.0;
  var filamentColor = vec3<f32>(0.0);
  let aspectVec = vec2<f32>(aspect, 1.0);
  for (var j = 0u; j < BALL_COUNT; j = j + 1u) {
      let a = orbPos[j];
      let b = orbPos[(j + 1u) % BALL_COUNT];
      let pa = (uv - a) * aspectVec;
      let ba = (b - a) * aspectVec;
      let along = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
      let strand = exp(-dot(pa - ba * along, pa - ba * along) / 0.00009);
      filament += strand;
      filamentColor += (orbCol[j] + orbCol[(j + 1u) % BALL_COUNT]) * 0.5 * strand;
  }
  let filamentMask = clamp(filament, 0.0, 1.0);
  finalColor += (filamentColor / max(filament, 0.001)) * filamentMask * (0.45 + audioMid * 0.2) * int_eval;

  // Idea 2 — luma corona: the field lights the bright parts of the photo.
  let photoLuma = dot(baseColor.rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
  let corona = plasmaField * smoothstep(0.08, 0.85, photoLuma);
  let coronaColor = plasmaColor / max(plasmaField, 0.001);
  finalColor += coronaColor * corona * (0.16 + audioHigh * 0.08) * int_eval;

  let coverage = clamp(plasmaField * 0.35 + filamentMask * 0.4, 0.0, 1.0);
  let alphaOut = clamp(baseColor.a * (1.0 - coverage * 0.35) + coverage, 0.0, 1.0);
  let display = aces(max(finalColor, vec3<f32>(0.0)));
  let pixel = vec2<i32>(global_id.xy);
  textureStore(writeTexture, pixel, vec4<f32>(display, alphaOut));
  textureStore(dataTextureA, pixel, vec4<f32>(display, alphaOut));

  let sceneDepth = textureLoad(readDepthTexture, pixel, 0).r;
  let relief = clamp(plasmaField * 0.15 + filamentMask * 0.2, 0.0, 1.0);
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(mix(sceneDepth, relief, 0.4), 0.0, 0.0, 0.0));
}
