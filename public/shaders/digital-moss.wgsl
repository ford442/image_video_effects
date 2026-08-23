// ═══════════════════════════════════════════════════════════════
//  Digital Moss — Batch 66
//  fp128 growth integration, CA propagation via exact C load,
//  racing scan pulses, wired sliders, spring brush [133..138],
//  ACES + semantic alpha.
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

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

const MOSS_DENSITY: f32 = 1.5;
const LEAF_SCATTERING: f32 = 1.8;
const YOUNG_MOSS_ALPHA: f32 = 0.45;
const DENSE_MOSS_ALPHA: f32 = 0.88;

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

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calculateMossThickness(growth: f32, age: f32) -> f32 {
    let maturity = smoothstep(0.0, 0.8, growth);
    let baseThickness = mix(0.1, 0.4, maturity);
    return baseThickness + age * 0.05;
}

fn mossSSS(growth: f32, lightExposure: f32) -> vec3<f32> {
    let chlorophyll = vec3<f32>(0.15, 0.85, 0.25);
    let scatter = lightExposure * LEAF_SCATTERING;
    let healthyColor = vec3<f32>(0.2, 0.95, 0.35);
    let sparseColor = vec3<f32>(0.5, 0.8, 0.2);
    let healthMix = smoothstep(0.3, 0.9, growth);
    let baseColor = mix(sparseColor, healthyColor, healthMix);
    return baseColor * chlorophyll * (1.0 + scatter * 0.3);
}

fn calculateMossAlpha(growth: f32, thickness: f32, scanline: f32) -> f32 {
    let growthAlpha = mix(YOUNG_MOSS_ALPHA, DENSE_MOSS_ALPHA, growth);
    let absorption = exp(-thickness * MOSS_DENSITY);
    let thicknessAlpha = mix(YOUNG_MOSS_ALPHA, growthAlpha, absorption);
    let scanAlpha = mix(thicknessAlpha, thicknessAlpha * 0.9, scanline * 0.3);
    let sparseFade = smoothstep(0.0, 0.15, growth);
    return clamp(scanAlpha * sparseFade + 0.2, 0.25, 0.92);
}

fn scan_pulse(uv: vec2<f32>, time: f32, density: f32, speed: f32) -> f32 {
  let head = fract(time * (0.6 + speed * 2.5));
  let d = abs(uv.y - head);
  return pow(max(0.0, 1.0 - d * (8.0 + density * 12.0)), 4.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);

    let time = u.config.x;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = mix(0.5, 3.0, u.zoom_params.z);
    let detail = u.zoom_params.w;
    let held = u.zoom_config.w > 0.5;
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    let rawMouse = u.zoom_config.yz;
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mouse = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
      mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
      var springPos = mouse;
      var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
      if (extraBuffer[138] <= 0.5) {
        springPos = rawMouse;
        springVel = vec2<f32>(0.0);
      } else {
        let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
        let omega = 10.0;
        let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
        springVel += accel * dt;
        springPos += springVel * dt;
      }
      extraBuffer[133] = springPos.x;
      extraBuffer[134] = springPos.y;
      extraBuffer[135] = springVel.x;
      extraBuffer[136] = springVel.y;
      extraBuffer[137] = time;
      extraBuffer[138] = 1.0;
    }

    let aspect = f32(dims.x) / f32(dims.y);
    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    let oldState = textureLoad(dataTextureC, coord, 0).r;
    let seed = hash12(uv * scale + vec2<f32>(time * 0.12 * speed, time * 0.06 * speed));

    var grown = oldState;
    let growthRate = fp128_mul(fp128(0.05 + intensity * 0.08), fp128(1.0 + bass * 0.3 + select(0.0, 0.2, held)));

    if (luma < 0.15 && seed > 0.995 - intensity * 0.003) {
        grown = 1.0;
    }

    if (grown < 0.9) {
        let angle = hash12(uv * 10.0 * scale + time * speed) * 6.28;
        let dist = 2.0;
        let offset = vec2<f32>(cos(angle), sin(angle)) * dist;
        let neighborCoord = coord + vec2<i32>(offset);
        let neighborState = textureLoad(dataTextureC, clamp(neighborCoord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
        if (neighborState > 0.5 && luma < 0.4) {
             grown = min(1.0, grown + fp128_val(growthRate));
        }
    }

    if (luma > 0.6) {
        grown *= 0.9;
    }

    let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let m_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let mouseDist = length(p_aspect - m_aspect);
    let brush = mix(0.05, 0.12, held);
    if (mouseDist < brush) {
        grown = 0.0;
    }

    textureStore(dataTextureA, coord, vec4<f32>(grown, 0.0, 0.0, grown));

    let mossThickness = calculateMossThickness(grown, grown * time * 0.1);
    let scanDensity = mix(200.0, 800.0, detail);
    let scan = 0.8 + 0.2 * sin(uv.y * scanDensity + time * (3.0 + speed * 8.0));
    let pulse = scan_pulse(uv, time, detail, speed);

    let lightExposure = 1.0 - luma;
    let mossColor = mossSSS(grown, lightExposure);
    let scannedMossColor = mossColor * scan * (1.0 + pulse * 0.25);
    let mossAlpha = calculateMossAlpha(grown, mossThickness, scan);

    var finalColor = mix(imgColor, scannedMossColor, grown * mossAlpha);
    finalColor = acesToneMap(finalColor);
    let alpha = clamp(mix(1.0, mossAlpha, grown) + pulse * grown * 0.08, 0.25, 0.98);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, alpha));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
