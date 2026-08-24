// ═══════════════════════════════════════════════════════════════════
//  Scanline Cyberpunk — Batch 66
//  fp128 glitch offset integration, racing head-roll + phosphor runner,
//  capped click fronts, held amplifies roll, scene depth preserved,
//  ACES + semantic alpha.
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

struct Fp128 {
  base: f32,
  mant: f32,
}

fn fp128(x: f32) -> Fp128 {
  return Fp128(x, 0.0);
}

fn fp128_sum(a: Fp128, b: Fp128) -> Fp128 {
  let s = a.base + b.base;
  let e = (a.base - s) + b.base + a.mant + b.mant;
  let t = s + e;
  let f = e - (t - s);
  return Fp128(t, f);
}

fn fp128_mul(a: Fp128, b: Fp128) -> Fp128 {
  let p = a.base * b.base;
  let e = a.base * b.mant + a.mant * b.base;
  let t = p + e;
  let f = e - (t - p);
  return Fp128(t, f);
}

fn fp128_val(x: Fp128) -> f32 {
  return x.base + x.mant;
}

fn hash(x: f32) -> f32 {
    return fract(sin(x * 127.1) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn colorGrade(col: vec3<f32>, strength: f32) -> vec3<f32> {
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let shadowTint   = vec3<f32>(0.05, 0.12, 0.15);
    let highlightTint = vec3<f32>(0.15, 0.08, 0.02);
    let shadowBlend    = (1.0 - luma) * (1.0 - luma);
    let highlightBlend = luma * luma;
    return col
        + shadowTint    * shadowBlend    * strength
        - highlightTint * highlightBlend * strength * 0.5
        + highlightTint * highlightBlend * strength;
}

fn phosphor_runner(uv: vec2<f32>, dims: vec2<f32>, time: f32) -> f32 {
  let phase = fp128_sum(fp128_mul(fp128(uv.x * dims.x * 0.55 + uv.y * 21.0), fp128(1.0)), fp128(-time * 18.0));
  return pow(max(0.0, sin(fp128_val(phase))), 14.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;
    let held = u.zoom_config.w > 0.5;

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mid    = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let scanlineStr  = mix(0.0, 0.7,  u.zoom_params.x);
    let phosphorStr  = mix(0.0, 0.5,  u.zoom_params.y);
    let glitchAmt    = mix(0.0, 0.04, u.zoom_params.z) * (1.0 + bass * 2.0) * select(1.0, 1.35, held);
    let gradeStr     = mix(0.0, 1.0,  u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let aspect = dims.x / dims.y;
    let mouseDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
    let mouseField = (1.0 - smoothstep(0.04, 0.34, mouseDist)) * select(0.25, 1.0, held);

    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.7) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            clickFront += smoothstep(0.022, 0.0, abs(length(delta) - age * 0.5)) * exp(-age * 1.6);
        }
    }

    let glitchBand = floor(uv.y * 20.0);
    let bandSeed = hash(glitchBand);
    let bandCarrier = sin(time * (8.0 + bass * 5.0) + bandSeed * 6.28318);
    let headRoll = pow(max(0.0, sin(uv.y * 68.0 - time * 15.0)), 15.0);

    let offsetPhase = fp128_sum(
      fp128_mul(fp128(bandCarrier * glitchAmt), fp128(0.25 + bass + mouseField * 0.8 + clickFront)),
      fp128(headRoll * glitchAmt * 1.5)
    );
    let glitchOffset = fp128_val(offsetPhase);
    var sampleUV = clamp(vec2<f32>(uv.x + glitchOffset, uv.y), vec2<f32>(0.0), vec2<f32>(1.0));

    let prev = textureLoad(dataTextureC, coord, 0);
    let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    var col = mix(src.rgb, prev.rgb * 0.9, headRoll * 0.15);

    let scanlineRow  = gid.y % 2u;
    let scanlineMask = select(1.0 - scanlineStr, 1.0, scanlineRow == 0u);
    col *= scanlineMask;

    let triadCol = gid.x % 3u;
    var phosphor = vec3<f32>(1.0);
    if (phosphorStr > 0.0) {
        let pDim = 1.0 - phosphorStr * 0.5;
        if      (triadCol == 0u) { phosphor = vec3<f32>(1.0,   pDim, pDim); }
        else if (triadCol == 1u) { phosphor = vec3<f32>(pDim,  1.0,  pDim); }
        else                     { phosphor = vec3<f32>(pDim,  pDim, 1.0 ); }
    }
    col *= phosphor;

    let phosphorRunner = phosphor_runner(uv, dims, time);
    col += phosphor * phosphorRunner * phosphorStr * (0.08 + treble * 0.12);

    let flicker = 1.0 + treble * 0.08 * sin(time * 60.0);
    col *= flicker;

    let lumaOrig    = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let neonOverlay = vec3<f32>(0.0, 0.9, 0.8) * lumaOrig * (0.08 + clickFront * 0.25) * (1.0 + mid);
    col += neonOverlay;

    col = colorGrade(col, gradeStr);
    col = acesToneMap(col);

    let alpha = clamp(src.a + clickFront * 0.08 + phosphorRunner * 0.05, 0.06, 0.98);
    let sceneDepth = textureLoad(readDepthTexture, coord, 0).r;

    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(sceneDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureB, coord, vec4<f32>(bass, mid, treble, glitchOffset));
}
