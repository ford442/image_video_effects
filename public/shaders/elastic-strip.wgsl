// ═══════════════════════════════════════════════════════════════════
//  Elastic Strip
//  Category: distortion
//  Features: mouse-driven, audio-reactive, spring-physics, depth-aware, upgraded-rgba
//  Complexity: High
//  Chunks From: elastic-strip, bass_env, depth-aware-fog
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn damped_oscillator(t: f32, freq: f32, decay: f32, phase: f32) -> f32 {
  return exp(-decay * t) * sin(t * freq + phase);
}

fn anisotropic_highlight(viewDir: vec2<f32>, lightDir: vec2<f32>, tangent: vec2<f32>, roughness: f32) -> f32 {
  let halfDir = normalize(viewDir + lightDir);
  let tdoth = max(dot(tangent, halfDir), 0.0);
  return pow(tdoth, 1.0 / max(roughness, 0.01));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let tension = mix(0.4, 1.6, depth);

    let stripCount = mix(8.0, 80.0, u.zoom_params.x) * (1.0 + bass * 0.3);
    let strength = (u.zoom_params.y - 0.5) * 2.5;
    let falloff = u.zoom_params.z;
    let direction = u.zoom_params.w;

    let isHoriz = step(0.5, direction);
    let stripCoord = mix(uv.x, uv.y, isHoriz);
    let mouseStrip = mix(mouse.x, mouse.y, isHoriz);
    let mouseDisplace = mix(mouse.y, mouse.x, isHoriz);

    let cell = floor(stripCoord * stripCount);
    let stripCenter = (cell + 0.5) / stripCount;
    let cellPhase = cell * 1.618;

    let dist = abs(stripCenter - mouseStrip);
    let influence = exp(-pow(dist / max(falloff * 0.5 + 0.01, 0.0001), 2.0));

    let pluckDecay = 2.0 + treble * 3.0;
    let pluckFreq = 6.0 + bass * 12.0;
    let springShift1 = damped_oscillator(time + cellPhase * 0.1, pluckFreq * tension, pluckDecay, cellPhase) * bass * 0.06;
    let springShift2 = damped_oscillator(time * 1.3 + cellPhase * 0.2, pluckFreq * 1.7 * tension, pluckDecay * 1.5, cellPhase + 1.0) * bass * 0.03;
    let dragShift = (mouseDisplace - 0.5) * strength * influence * tension;
    let totalShift = dragShift + (springShift1 + springShift2) * influence;

    let sourceUV = vec2<f32>(
        uv.x - select(0.0, totalShift, isHoriz > 0.5),
        uv.y - select(totalShift, 0.0, isHoriz > 0.5)
    );
    let clampedUV = clamp(sourceUV, vec2<f32>(0.0), vec2<f32>(1.0));

    let baseColor = textureSampleLevel(readTexture, u_sampler, clampedUV, 0.0);

    let chromaShift = abs(totalShift) * 0.025 * (1.0 + treble);
    let rUV = clamp(sourceUV + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sourceUV - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var rgb = vec3<f32>(r, baseColor.g, b);

    let stripEdge = abs(fract(stripCoord * stripCount) - 0.5) * 2.0;
    let edgeGlow = smoothstep(0.85, 1.0, stripEdge) * influence;

    let normal = vec2<f32>(select(1.0, 0.0, isHoriz > 0.5), select(0.0, 1.0, isHoriz > 0.5));
    let lightDir = normalize(vec2<f32>(0.3, 0.7));
    let viewDir = normalize(vec2<f32>(0.0, 0.0) - uv + 0.5);
    let ndotl = max(dot(normal, lightDir), 0.0);
    let specular = pow(ndotl, 32.0) * mids * 0.5;
    let aniso = anisotropic_highlight(viewDir, lightDir, normal, 0.15 + treble * 0.2) * mids * 0.4;

    let subsurface = edgeGlow * vec3<f32>(0.8, 0.3, 0.1) * (1.0 + bass * 0.5);
    rgb += subsurface * 0.35;
    rgb += vec3<f32>(specular + aniso);

    let plasticSheen = pow(1.0 - abs(dot(viewDir, normal)), 3.0) * 0.15 * (1.0 + treble);
    rgb += vec3<f32>(plasticSheen);

    rgb = aces_tonemap(rgb * (1.0 + edgeGlow * 0.3));

    let deformationEnergy = abs(totalShift) * 4.0;
    let alpha = clamp(baseColor.a * 0.6 + deformationEnergy * depth + edgeGlow * 0.2, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
