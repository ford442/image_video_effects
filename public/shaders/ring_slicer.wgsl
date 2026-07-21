// ═══════════════════════════════════════════════════════════════════
//  Ring Slicer
//  Category: distortion
//  Features: polar-warp, mouse-driven, ring-rotation, fbm-wobble,
//            palette-seams, audio-reactive, mouse-grab-twist
//  Upgraded by: kimi-swarm 2026-07-19
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

// ── Hashes & Noise (canonical forms) ─────────────────────────────
fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let s = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                    hash21(i + vec2<f32>(1.0, 0.0)), s.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), s.x),
        s.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum  += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp  *= 0.5;
    }
    return sum;
}

// ── Color helpers ────────────────────────────────────────────────
fn cosPalette(t: f32) -> vec3<f32> {
    return vec3<f32>(0.5) + vec3<f32>(0.5) * cos(6.2831853 * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  var mousePos = u.zoom_config.yz;
  let mouseDown = clamp(u.zoom_config.w, 0.0, 1.0);
  let time = u.config.x;

  // Params (normalized before use) — labels preserved from catalog
  let density = mix(2.0, 22.0, clamp(u.zoom_params.x, 0.0, 1.0));   // Ring Count
  let speed = (clamp(u.zoom_params.y, 0.0, 1.0) - 0.5) * 4.0;       // Rotation Speed
  let chaos = clamp(u.zoom_params.z, 0.0, 1.0);                     // Chaos
  let mouseInfluence = clamp(u.zoom_params.w, 0.0, 1.0);            // Mouse Follow

  // Audio (subtle; silent when no audio buffer is wired)
  var bass = 0.0;
  var mids = 0.0;
  if (arrayLength(&plasmaBuffer) > 0u) {
      bass = clamp(plasmaBuffer[0].x, 0.0, 1.5);
      mids = clamp(plasmaBuffer[0].y, 0.0, 1.5);
  }

  var center = vec2<f32>(0.5, 0.5);
  let aspect = resolution.x / max(resolution.y, 0.001);

  if (mouseInfluence > 0.1 && mousePos.x >= 0.0) {
      center = mix(center, mousePos, mouseInfluence);
  }

  var dVec = uv - center;
  dVec.x *= aspect;

  let r = length(dVec);
  let a = atan2(dVec.y, dVec.x);

  // ── Organic wobble: warp the radius used for ring slicing ──────
  // Angular noise coordinate lives on the unit circle so the wobble
  // wraps seamlessly at the ±π atan2 boundary.
  let wobbleCoord = vec2<f32>(cos(a), sin(a)) * 2.0 + vec2<f32>(r * 3.0, -r * 2.0);
  let wobble = fbm(wobbleCoord + vec2<f32>(time * 0.12, -time * 0.09), 3) - 0.5;
  let rSliced = max(r + wobble * 0.08 * chaos, 0.0);

  let ringIndex = floor(rSliced * density);

  let direction = select(-1.0, 1.0, (ringIndex % 2.0) == 0.0);

  let randFactor = hash12(vec2<f32>(ringIndex, 1.0));
  let chaosSpeed = mix(1.0, 0.5 + randFactor * 2.0, chaos);

  // ── Rotation: base spin + bass pulse + mouse-down grab-twist ───
  let angleOffset = time * speed * direction * chaosSpeed * (1.0 + bass * 0.5) * (1.0 + mouseDown * 1.5);
  let grabTwist = mouseDown * 1.2 / (r * 6.0 + 1.0);
  let newAngle = a + angleOffset + grabTwist;

  let newX = r * cos(newAngle);
  let newY = r * sin(newAngle);

  let warpedUV = vec2<f32>(newX / aspect, newY) + center;

  let finalUV = fract(warpedUV);

  var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

  // ── Seam glow: smooth bands tinted by a drifting cosine palette ─
  let ringPos = fract(rSliced * density);
  let seamDist = min(ringPos, 1.0 - ringPos);
  let edgeWidth = 0.03 + 0.09 * chaos;
  let seam = 1.0 - smoothstep(0.0, edgeWidth, seamDist);
  let seamStrength = (0.15 + 0.85 * chaos) * (1.0 + mids * 0.8);
  let seamColor = cosPalette(ringIndex * 0.13 + time * 0.05 + mids * 0.15);
  color = vec4<f32>(color.rgb + seamColor * seam * seamStrength * 0.35, color.a);

  // ── Soft-knee highlight compression (image ≤ 1.0 stays untouched)
  let l = luma(color.rgb);
  color = vec4<f32>(mix(color.rgb, acesToneMap(color.rgb), smoothstep(1.0, 1.6, l)), clamp(color.a, 0.0, 1.0));

  textureStore(writeTexture, vec2<i32>(global_id.xy), color);

  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
