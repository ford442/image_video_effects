// ═══════════════════════════════════════════════════════════════════
//  Sentient Void-Silk Nebula
//  Category: generative
//  Features: mouse-driven, audio-reactive, temporal-feedback, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15
//  Ideas: three-strand braided fibrils; opposing-curl tension knots
//  A packing: ACES display RGBA
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Flow Speed, .y = Thread Density, .z = Vortex Strength, .w = Iridescence Shift
  ripples: array<vec4<f32>, 50>,
};

// --- Constants & Utilities ---
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

// 3D Curl Noise implementation
fn mod289(x: vec4<f32>) -> vec4<f32> {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}
fn permute(x: vec4<f32>) -> vec4<f32> {
  return mod289(((x*34.0)+1.0)*x);
}
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> {
  return 1.79284291400159 - 0.85373472095314 * r;
}

fn snoise(v: vec3<f32>) -> f32 {
  let C = vec2<f32>(1.0/6.0, 1.0/3.0);
  let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

  var i  = floor(v + dot(v, C.yyy));
  let x0 = v - i + dot(i, C.xxx);

  let g = step(x0.yzx, x0.xyz);
  let l = 1.0 - g;
  let i1 = min(g.xyz, l.zxy);
  let i2 = max(g.xyz, l.zxy);

  let x1 = x0 - i1 + C.xxx;
  let x2 = x0 - i2 + C.yyy;
  let x3 = x0 - D.yyy;

  let i_mod = mod289(vec4<f32>(i.x, i.y, i.z, 0.0));
  let p = permute(permute(permute(
             vec4<f32>(i_mod.z) + vec4<f32>(0.0, i1.z, i2.z, 1.0) )
           + vec4<f32>(i_mod.y) + vec4<f32>(0.0, i1.y, i2.y, 1.0) )
           + vec4<f32>(i_mod.x) + vec4<f32>(0.0, i1.x, i2.x, 1.0) );

  let n_ = 0.142857142857;
  let ns = n_ * D.wyz - D.xzx;

  let j = p - 49.0 * floor(p * ns.z * ns.z);

  let x_ = floor(j * ns.z);
  let y_ = floor(j - 7.0 * x_);

  let x = x_ *ns.x + ns.yyyy;
  let y = y_ *ns.x + ns.yyyy;
  let h = 1.0 - abs(x) - abs(y);

  let b0 = vec4<f32>(x.xy, y.xy);
  let b1 = vec4<f32>(x.zw, y.zw);

  let s0 = floor(b0)*2.0 + 1.0;
  let s1 = floor(b1)*2.0 + 1.0;
  let sh = -step(h, vec4<f32>(0.0));

  let a0 = vec4<f32>(b0.x, b0.z, b0.y, b0.w) + vec4<f32>(s0.x, s0.z, s0.y, s0.w) * vec4<f32>(sh.x, sh.x, sh.y, sh.y);
  let a1 = vec4<f32>(b1.x, b1.z, b1.y, b1.w) + vec4<f32>(s1.x, s1.z, s1.y, s1.w) * vec4<f32>(sh.z, sh.z, sh.w, sh.w);

  var p0 = vec3<f32>(a0.xy, h.x);
  var p1 = vec3<f32>(a0.zw, h.y);
  var p2 = vec3<f32>(a1.xy, h.z);
  var p3 = vec3<f32>(a1.zw, h.w);

  let norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 = p0 * norm.x;
  p1 = p1 * norm.y;
  p2 = p2 * norm.z;
  p3 = p3 * norm.w;

  var m = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
  m = m * m;
  return 42.0 * dot( m*m, vec4<f32>( dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3) ) );
}

fn curlNoiseRaw(p: vec3<f32>) -> vec3<f32> {
    let e = 0.1;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let p_x0 = snoise(p - dx);
    let p_x1 = snoise(p + dx);
    let p_y0 = snoise(p - dy);
    let p_y1 = snoise(p + dy);
    let p_z0 = snoise(p - dz);
    let p_z1 = snoise(p + dz);

    let x = p_y1 - p_y0 - p_z1 + p_z0;
    let y = p_z1 - p_z0 - p_x1 + p_x0;
    let z = p_x1 - p_x0 - p_y1 + p_y0;

    return vec3<f32>(x, y, z) / (2.0 * e);
}

fn safeNormalize3(v: vec3<f32>) -> vec3<f32> {
    return v / max(length(v), 0.0001);
}

fn safeNormalize2(v: vec2<f32>) -> vec2<f32> {
    return v / max(length(v), 0.0001);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp(
        (x * (a * x + b)) / (x * (c * x + d) + e),
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dimensions = vec2<u32>(u32(u.config.z), u32(u.config.w));
    if (global_id.x >= dimensions.x || global_id.y >= dimensions.y) { return; }

    let res = vec2<f32>(dimensions);
    // Base UVs
    let base_uv = (vec2<f32>(coords) + 0.5) / res;
    let uv = base_uv * 2.0 - 1.0;

    // Core parameters from UI
    let flowSpeed = u.zoom_params.x;
    let threadDensity = u.zoom_params.y;
    let vortexStrength = u.zoom_params.z;
    let iridescence = u.zoom_params.w;

    // Canonical three-band audio; no reserved extraBuffer pseudo-audio.
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioPull = bass * 0.22;

    // Base 3D coordinate driven by time and uv
    let p = vec3<f32>(uv * 2.0, u.config.x * flowSpeed * 0.1);

    // Interaction logic
    var divergence = p;
    if (u.zoom_config.w > 0.0) {
        let mouseDelta = uv - (u.zoom_config.yz * 2.0 - 1.0);
        let mouseDist = max(length(mouseDelta), 0.0001);
        let radial = mouseDelta / mouseDist;
        let swirl = vec2<f32>(-radial.y, radial.x);
        let pull = exp(-mouseDist * 4.0) * vortexStrength;
        divergence.x += pull * (swirl.x * 0.52 - radial.x * 0.2);
        divergence.y += pull * (swirl.y * 0.52 - radial.y * 0.2);
    }

    // Audio attraction to center
    divergence -= safeNormalize3(vec3<f32>(uv, 0.0)) * audioPull;

    // Evaluate silk field
    let fieldPoint = divergence * threadDensity;
    let rawField = curlNoiseRaw(fieldPoint);
    let field = safeNormalize3(rawField);
    let tangent = safeNormalize2(field.xy + vec2<f32>(0.0001, 0.0));
    let side = vec2<f32>(-tangent.y, tangent.x);
    let along = dot(divergence.xy, tangent);
    let across = dot(divergence.xy, side);

    // Structural color
    let tension = clamp(length(rawField) * 0.18, 0.0, 2.5);
    let silkPhase =
        along * (10.0 + threadDensity * 2.5)
        - u.config.x * flowSpeed * 0.8
        + snoise(fieldPoint * 0.42) * 1.4;

    // Idea 1 — three phase-offset fibrils orbit a shared curl tangent.
    let braidRadius = 0.035 + 0.018 * clamp(threadDensity / 5.0, 0.0, 1.0);
    let braidSharpness = 22.0 + threadDensity * 7.0;
    let strand0 = exp(-pow((across - sin(silkPhase) * braidRadius) * braidSharpness, 2.0));
    let strand1 = exp(-pow((across - sin(silkPhase + TAU / 3.0) * braidRadius) * braidSharpness, 2.0));
    let strand2 = exp(-pow((across - sin(silkPhase + 2.0 * TAU / 3.0) * braidRadius) * braidSharpness, 2.0));
    let braid = clamp(strand0 + strand1 + strand2, 0.0, 1.5);
    let braidColor =
        palette(iridescence + 0.00 + field.z * 0.12) * strand0
        + palette(iridescence + 0.18 + field.z * 0.12) * strand1
        + palette(iridescence + 0.36 + field.z * 0.12) * strand2;

    // Idea 2 — opposed neighboring curls pinch into compact knots, while
    // a narrow, slower falloff along the tangent forms caustic tails.
    let neighborRaw = curlNoiseRaw(fieldPoint + vec3<f32>(side * 0.18, 0.07));
    let neighborField = safeNormalize3(neighborRaw);
    let opposition = smoothstep(0.05, 0.82, -dot(field, neighborField));
    let knotPhase =
        along * (3.4 + threadDensity * 0.65)
        + snoise(fieldPoint * 0.7 + vec3<f32>(4.7, 1.3, 2.9)) * 2.0
        - u.config.x * flowSpeed * 0.3;
    let knotCycle = 0.5 + 0.5 * cos(knotPhase);
    let knotCore =
        opposition
        * pow(knotCycle, 18.0)
        * exp(-pow(across * (36.0 + threadDensity * 4.0), 2.0));
    let causticTail =
        opposition
        * pow(knotCycle, 3.0)
        * exp(-pow(across * (17.0 + threadDensity * 2.0), 2.0));

    let baseColor = palette(
        tension * 0.16 + iridescence + u.config.x * 0.05 + bass * 0.025
    );
    var radiance = baseColor * (0.08 + tension * 0.14);
    radiance += braidColor * (0.65 + mids * 0.18);
    radiance += vec3<f32>(1.55, 1.28, 1.08) * knotCore * (1.0 + treble * 0.35);
    radiance += palette(iridescence + 0.62) * causticTail * (0.32 + treble * 0.16);

    // Slow exact A/C display-history blending preserves the silk drift.
    let currentDisplay = acesToneMap(radiance);
    let past = textureLoad(dataTextureC, coords, 0);
    let blend = clamp(0.045 + flowSpeed * 0.012, 0.045, 0.09);
    let finalColor = mix(past.rgb, currentDisplay, blend);
    let currentAlpha = clamp(
        0.08 + tension * 0.08 + braid * 0.42 + knotCore * 0.34,
        0.0,
        0.96
    );
    let finalAlpha = mix(past.a, currentAlpha, blend);
    let depth = clamp(
        0.18 + tension * 0.12 + braid * 0.38 + knotCore * 0.18,
        0.0,
        1.0
    );

    textureStore(writeTexture, coords, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coords, vec4<f32>(finalColor, finalAlpha));
}
