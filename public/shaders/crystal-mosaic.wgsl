// ═══════════════════════════════════════════════════════════════════
//  Crystal Mosaic — Refraction Lighting & Caustics Enhanced
//  Category: geometric
//  Features: mouse-driven, audio-reactive, depth-parallax, chromatic-edges,
//            crystal-refraction, caustics, rim-lighting, subsurface-scattering
//  Complexity: High
//  Created: 2026-05-31
//  Enhanced: 2026-06-28
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

fn hash21(p: vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let h = hash21(p);
  return vec2<f32>(h, fract(h * 43758.5453));
}

fn noise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ═══ Crystal Fresnel Falloff ═══
fn crystalFresnel(cosTheta: f32, F0: f32) -> f32 {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ═══ Caustics Simulation (projected light patterns through crystal) ═══
fn caustics(uv: vec2<f32>, time: f32, intensity: f32) -> vec3<f32> {
  let p = uv * 8.0;
  var caustic = 0.0;
  // Overlapping wave interference patterns
  caustic = caustic + sin(p.x * 3.0 + time * 1.5) * cos(p.y * 2.5 - time * 1.2);
  caustic = caustic + sin(p.x * 2.0 - p.y * 3.0 + time * 2.0) * 0.5;
  caustic = caustic + sin(length(p) * 4.0 - time * 3.0) * 0.3;
  caustic = caustic * 0.5 + 0.5;
  caustic = pow(caustic, 3.0); // Sharpen caustic bands

  // Warm caustic color: golden + cyan mix
  let warmCaustic = vec3<f32>(1.0, 0.85, 0.5) * caustic * intensity;
  let coolCaustic = vec3<f32>(0.5, 0.85, 1.0) * (1.0 - caustic) * intensity * 0.5;
  return warmCaustic + coolCaustic;
}

// ═══ Rim Lighting ═══
fn rimLighting(viewDir: vec3<f32>, normal: vec3<f32>, strength: f32) -> f32 {
  let rim = 1.0 - max(dot(viewDir, normal), 0.0);
  return pow(rim, 3.0) * strength;
}

// ═══ Subsurface Scattering Glow (light penetrating crystal) ═══
fn subsurfaceGlow(uv: vec2<f32>, lightPos: vec2<f32>, thickness: f32, intensity: f32) -> f32 {
  let d = length(uv - lightPos);
  // Light penetrates thin crystal edges, scatters inside
  let penetration = exp(-d * d * 8.0) * thickness;
  let scatter = exp(-d * 3.0) * 0.5;
  return (penetration + scatter) * intensity;
}

// ═══ Light Attenuation ═══
fn lightAttenuation(d: f32, k: f32, q: f32) -> f32 {
  return 1.0 / (1.0 + k * d + q * d * d);
}

// ═══ Chromatic Aberration at Tile Edges ═══
fn chromaticAberration(uv: vec2<f32>, edgeStrength: f32, radialOffset: f32) -> vec3<f32> {
  let center = vec2<f32>(0.5);
  let d = uv - center;
  let radialDist = length(d);
  let offset = radialDist * radialOffset * edgeStrength;
  let rUV = uv + d * offset * 1.0;
  let gUV = uv + d * offset * 0.5;
  let bUV = uv + d * offset * 1.5;
  let r = textureSampleLevel(readTexture, u_sampler, clamp(rUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
  let g = textureSampleLevel(readTexture, u_sampler, clamp(gUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
  let b = textureSampleLevel(readTexture, u_sampler, clamp(bUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthShift = mix(-0.02, 0.02, depth);

    let density = mix(5.0, 40.0, u.zoom_params.x);
    let rotationAmt = u.zoom_params.y;
    let chromaticEdge = u.zoom_params.z * 0.01;
    let mouseInfluence = u.zoom_params.w;

    let s = uv * density;
    let i = floor(s.x);
    let j = floor(s.y * 0.8660254);
    let rowParity = i32(j) & 1;
    let u_frac = fract(s.x);
    let v_frac = fract(s.y * 0.8660254);

    // Triangle inside rhombus
    let triID = vec2<f32>(i + f32(rowParity) * 0.5, j);
    let triCenter = (triID + vec2<f32>(0.5, 0.57735)) / density;

    let dToMouse = length(triCenter - mousePos);
    let influence = smoothstep(0.4, 0.0, dToMouse) * mouseInfluence;

    // Rotate triangle based on mouse + audio
    let rot = (rotationAmt + influence + bass * 0.1) * 0.5;
    let localUV = uv - triCenter;
    let c = cos(rot);
    let s_rot = sin(rot);
    let rotatedUV = vec2<f32>(
        localUV.x * c - localUV.y * s_rot,
        localUV.x * s_rot + localUV.y * c
    ) + triCenter + vec2<f32>(depthShift, depthShift);

    // Edge factor for chromatic aberration
    let edge = smoothstep(0.15, 0.0, abs(v_frac - 0.5) + abs(u_frac - 0.5) * 0.5);

    // ═══ CRYSTAL REFRACTION SAMPLING ═══
    // Apply chromatic aberration at tile edges
    var refractedColor = chromaticAberration(rotatedUV, edge * chromaticEdge * (1.0 + bass), 0.02);

    // Standard RGB split for comparison
    let rUV = clamp(rotatedUV + vec2<f32>(chromaticEdge * edge * (1.0 + bass), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(rotatedUV - vec2<f32>(chromaticEdge * edge * (1.0 + treble), 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, rotatedUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;

    // Blend refracted and standard sampling based on edge strength
    var color = mix(vec3<f32>(r, g, b), refractedColor, edge * 0.5);

    // ═══ CAUSTICS LIGHTING ═══
    // Project caustics onto tile surfaces, animated by time
    let causticIntensity = 0.5 + mids * 0.5 + influence * 0.3;
    let causticColor = caustics(triCenter + time * 0.05, time, causticIntensity);
    color = color + causticColor * edge * (0.3 + bass * 0.2);

    // ═══ CRYSTAL FRESNEL REFLECTIONS ═══
    // Build approximate normal from tile orientation
    let tileNormal = normalize(vec3<f32>(cos(rot), sin(rot), 0.5 + edge * 0.5));
    let viewDir = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));
    let cosTheta = max(dot(viewDir, tileNormal), 0.0);
    let fresnel = crystalFresnel(cosTheta, 0.04); // Glass F0
    // Reflect environment color based on fresnel
    let envReflect = vec3<f32>(0.6, 0.7, 0.8) * fresnel * (0.5 + treble * 0.3);
    color = color + envReflect * edge;

    // ═══ RIM LIGHTING ON TILE EDGES ═══
    let rim = rimLighting(viewDir, tileNormal, 1.0 + bass * 1.5);
    let rimColor = vec3<f32>(0.8, 0.9, 1.0) * rim * edge * (0.5 + influence * 0.5);
    color = color + rimColor;

    // ═══ SUBSURFACE SCATTERING GLOW ═══
    // Light penetrates thin crystal edges
    let thickness = 1.0 - edge; // Thinner at edges
    let sssGlow = subsurfaceGlow(uv, mousePos, thickness, 0.8 + mids * 0.5);
    let sssColor = mix(vec3<f32>(0.9, 0.6, 0.3), vec3<f32>(0.3, 0.6, 0.9), sin(time + triID.x * 0.5) * 0.5 + 0.5);
    color = color + sssColor * sssGlow * influence * 0.4;

    // Tile border highlight with light attenuation
    let borderDist = min(min(u_frac, 1.0 - u_frac), min(v_frac, 1.0 - v_frac));
    let border = smoothstep(0.05, 0.0, borderDist) * mids;
    let borderAtten = lightAttenuation(borderDist * 20.0, 0.1, 0.05);
    color = color + vec3<f32>(0.3, 0.2, 0.4) * border * borderAtten;

    // ═══ AUDIO-REACTIVE SPARKLE ON CRYSTAL FACETS ═══
    let sparkle = hash21(triID + time * 0.2) * treble * edge * 0.5;
    color = color + vec3<f32>(1.0, 0.95, 0.85) * sparkle;

    // Bloom-weighted alpha
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.85 + border * 0.15 + luma * 0.2 + bass * 0.05 + edge * 0.1, 0.0, 1.0);

    // Premultiplied alpha writeback
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color * alpha, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
