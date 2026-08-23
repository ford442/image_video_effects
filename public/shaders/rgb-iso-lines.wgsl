// ═══════════════════════════════════════════════════════════════
//  RGB ISO Lines
//  Category: artistic
//  Features: parallax, contour-lines, wavelength-dependent-alpha,
//            audio-reactive, upgraded-rgba, iso-runners, held-drag,
//            bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23
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

const WAVELENGTH_RED: f32 = 650.0;
const WAVELENGTH_GREEN: f32 = 550.0;
const WAVELENGTH_BLUE: f32 = 450.0;

fn calculateChannelAlpha(thickness: f32, wavelength: f32) -> f32 {
    let lambda_norm = (800.0 - wavelength) / 400.0;
    let absorption = mix(0.3, 1.0, lambda_norm);
    return exp(-thickness * absorption);
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let pixel = vec2<i32>(global_id.xy);
  let dims = vec2<i32>(textureDimensions(writeTexture));
  if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }

  let uv = vec2<f32>(pixel) / vec2<f32>(dims);
  let time = u.config.x;
  let held = f32(u.zoom_config.w > 0.5);
  let mouse = u.zoom_config.yz;
  let prev = textureLoad(dataTextureC, pixel, 0);
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  let thickness = mix(0.01, 0.45, u.zoom_params.x) * (1.0 + mids * 0.4);
  let freq = mix(5.0, 50.0, u.zoom_params.y) * (1.0 + bass * 0.5);
  let parallax_amt = mix(0.0, 0.1, u.zoom_params.z) * (1.0 + treble * 0.5) * (1.0 + held * 0.35);
  let offset = (mouse - vec2<f32>(0.5)) * parallax_amt;

  let r_val = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g_val = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
  let b_val = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  let line_width = thickness * 0.5;
  let r_line = smoothstep(0.5 - line_width - 0.02, 0.5 - line_width, abs(fract(r_val * freq) - 0.5));
  let g_line = smoothstep(0.5 - line_width - 0.02, 0.5 - line_width, abs(fract(g_val * freq) - 0.5));
  let b_line = smoothstep(0.5 - line_width - 0.02, 0.5 - line_width, abs(fract(b_val * freq) - 0.5));
  let line_col = vec3<f32>(r_line, g_line, b_line);
  let base = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb * mix(0.0, 0.5, u.zoom_params.w);
  var final_col = line_col + base;

  let runners = smoothstep(0.09, 0.0, abs(fract((r_val + g_val) * freq * 0.5 - time * (1.7 + bass * 2.0)) - 0.5));
  let ticks = smoothstep(0.08, 0.0, abs(fract(uv.y * freq * 0.35 + time * 0.9) - 0.5));
  var click = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];
    let age = time - rp.z;
    if (rp.z > 0.0 && age >= 0.0 && age < 1.4) {
      click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.48) * 66.0) * (1.0 - age / 1.4));
    }
  }
  let slick = hsv2rgb(vec3<f32>(fract(g_val + time * 0.1 + mids * 0.2), 0.72, 1.0));
  final_col = mix(final_col, final_col * slick * 1.25, 0.28 + treble * 0.18);
  final_col += slick * (runners * 0.26 + ticks * 0.18 + click * 0.5);

  let parallaxLength = length(offset);
  let dispersionThickness = parallaxLength * 10.0;
  let alphaR = calculateChannelAlpha(dispersionThickness, WAVELENGTH_RED);
  let alphaG = calculateChannelAlpha(dispersionThickness, WAVELENGTH_GREEN);
  let alphaB = calculateChannelAlpha(dispersionThickness, WAVELENGTH_BLUE);
  let finalAlpha = clamp(dot(vec3<f32>(alphaR, alphaG, alphaB), vec3<f32>(0.299, 0.587, 0.114)) + click * 0.1, 0.0, 1.0);
  let alphaModulatedColor = vec3<f32>(final_col.r * alphaR, final_col.g * alphaG, final_col.b * alphaB);
  let outCol = vec4<f32>(mix(alphaModulatedColor, prev.rgb * 0.86, 0.22), mix(finalAlpha, prev.a * 0.86, 0.22));
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  textureStore(writeTexture, pixel, outCol);
  textureStore(dataTextureA, pixel, vec4<f32>(r_line, g_line, b_line, outCol.a));
  textureStore(writeDepthTexture, pixel, vec4<f32>(clamp(depth + (r_line + g_line + b_line) * 0.04, 0.0, 1.0), 0.0, 0.0, 0.0));
}
