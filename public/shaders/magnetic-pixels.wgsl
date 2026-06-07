// ═══════════════════════════════════════════════════════════════════
//  Magnetic Pixels v2
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, depth-aware, upgraded-rgba
//  Complexity: High
//  Strategy: Dipole field simulation + Lorentz force + iron-filing aesthetic
//  Upgraded: 2026-05-30
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash12 (common) ═══
fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
  p3 = p3 + dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// ═══ CHUNK: aces_tone_map ═══
fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = vec3<f32>(2.51, 2.51, 2.51);
  let b = vec3<f32>(0.03, 0.03, 0.03);
  let c = vec3<f32>(2.43, 2.43, 2.43);
  let d = vec3<f32>(0.59, 0.59, 0.59);
  let e = vec3<f32>(0.14, 0.14, 0.14);
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Dipole magnetic field B = (3(m·r)r - m|r|²) / |r|⁵
fn dipole_field(pos: vec2<f32>, dipolePos: vec2<f32>, moment: vec2<f32>) -> vec2<f32> {
  let r = pos - dipolePos;
  let r2 = dot(r, r);
  let r2_safe = max(r2, 0.0001);
  let invR5 = 1.0 / (r2_safe * r2_safe * sqrt(r2_safe));
  let m_dot_r = dot(moment, r);
  return (3.0 * m_dot_r * r - moment * r2_safe) * invR5;
}

// Vector potential A = cross(m, r) / |r|³  (scalar in 2D)
fn vector_potential(pos: vec2<f32>, dipolePos: vec2<f32>, moment: vec2<f32>) -> f32 {
  let r = pos - dipolePos;
  let r2 = dot(r, r);
  let r2_safe = max(r2, 0.0001);
  return (moment.x * r.y - moment.y * r.x) / (r2_safe * sqrt(r2_safe));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
  let coord = vec2<i32>(global_id.xy);
  let uv = vec2<f32>(global_id.xy) / resolution;
  let time = u.config.x;
  let mousePos = u.zoom_config.yz;
  let mouseDown = u.zoom_config.w > 0.5;
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;

  let dipoleStrength = u.zoom_params.x * (1.0 + bass * 0.6);
  let fieldRadius = max(u.zoom_params.y * 0.5, 0.02);
  let metallic = u.zoom_params.z;
  let chromaAmt = u.zoom_params.w * 0.015;

  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  let depthScale = mix(0.6, 1.4, depth);

  // Dipole moment rotates with time and bass
  let angle = time * 0.8 + bass * 1.5;
  let dipoleMoment = vec2<f32>(cos(angle), sin(angle)) * dipoleStrength;

  // Mouse acts as movable dipole; when not active, dipole is at center
  let hasMouse = mousePos.x >= 0.0;
  let dipolePos = select(vec2<f32>(0.5, 0.5), mousePos, hasMouse);

  // Sample base color with chromatic aberration along dipole axis
  let aspect = resolution.x / resolution.y;
  let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
  let dipoleAspect = vec2<f32>(dipolePos.x * aspect, dipolePos.y);
  let axis = normalize(uvAspect - dipoleAspect + vec2<f32>(0.0001));

  let rUV = clamp(uv + vec2<f32>(axis.x * chromaAmt / aspect, axis.y * chromaAmt), vec2<f32>(0.0), vec2<f32>(1.0));
  let bUV = clamp(uv - vec2<f32>(axis.x * chromaAmt / aspect, axis.y * chromaAmt), vec2<f32>(0.0), vec2<f32>(1.0));
  let colR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let colG = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let colB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  let baseColor = vec3<f32>(colR.r, colG.g, colB.b);

  // Magnetic field at this pixel
  let B = dipole_field(uvAspect, dipoleAspect, dipoleMoment * fieldRadius * depthScale);
  let Bmag = length(B);
  let Bnorm = normalize(B + vec2<f32>(0.0001));

  // Vector potential for Lorentz-like displacement
  let A = vector_potential(uvAspect, dipoleAspect, dipoleMoment * fieldRadius);
  let lorentzDisp = vec2<f32>(-Bnorm.y, Bnorm.x) * A * 0.008 * dipoleStrength;

  // Iron-filing alignment: sample displaced by field direction
  let filingUV = clamp(uv + vec2<f32>(lorentzDisp.x / aspect, lorentzDisp.y), vec2<f32>(0.0), vec2<f32>(1.0));
  let filingColor = textureSampleLevel(readTexture, u_sampler, filingUV, 0.0).rgb;

  // Metallic sheen based on field alignment with screen X axis
  let alignment = abs(Bnorm.x);
  let sheen = vec3<f32>(0.85, 0.78, 0.65) * alignment * Bmag * metallic * 0.4;
  let filingTint = mix(vec3<f32>(0.92, 0.88, 0.82), vec3<f32>(1.0, 0.95, 0.85), alignment);

  // HDR bloom on field concentration
  let bloom = vec3<f32>(1.0, 0.92, 0.75) * Bmag * Bmag * 0.06 * (1.0 + mids * 0.5);

  let combined = filingColor * filingTint + sheen + bloom;
  let tonemapped = aces_tonemap(combined * (1.0 + bass * 0.2));

  // Alpha = field alignment confidence × depth
  let alignmentConf = smoothstep(0.0, 0.3, Bmag) * alignment;
  let alpha = clamp(alignmentConf * depth + 0.25, 0.0, 1.0);

  textureStore(writeTexture, coord, vec4<f32>(tonemapped, alpha));
  textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, coord, vec4<f32>(Bnorm, Bmag, alpha));
}
