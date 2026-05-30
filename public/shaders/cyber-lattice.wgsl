// ═══════════════════════════════════════════════════════════════════
//  Cyber Lattice
//  Category: image
//  Features: mouse-driven, audio-reactive, depth-aware, holographic-interference, upgraded-rgba
//  Complexity: High
//  Chunks From: cyber-lattice, warpedFBM, bass_env, thin-film-interference
//  Created: 2026-05-10
//  Upgraded: 2026-05-31
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
  zoom_params: vec4<f32>,  // x=GridScale, y=DistortStrength, z=GlowIntensity, w=Radius
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

fn thinFilm(d: f32, n: f32) -> vec3<f32> {
  let phase = d * n * 6.28318530718;
  let r = 0.5 + 0.5 * cos(phase);
  let g = 0.5 + 0.5 * cos(phase + 2.094);
  let b = 0.5 + 0.5 * cos(phase + 4.188);
  return vec3<f32>(r, g, b);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let gridScale = 10.0 + u.zoom_params.x * 50.0;
    let distortStrength = u.zoom_params.y * bass_env(bass, mids);
    let glowIntensity = u.zoom_params.z * 2.0;
    let radius = u.zoom_params.w * 0.5;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthParallax = (depth - 0.5) * 0.08;

    let aspect = resolution.x / max(resolution.y, 0.0001);
    let p = (uv - 0.5) * vec2<f32>(aspect, 1.0);

    // 3D perspective projection toward vanishing point
    let vanish = (mousePos - 0.5) * vec2<f32>(aspect, 1.0);
    let toVanish = p - vanish;
    let zDepth = length(toVanish) * 2.0 + 0.1;
    let persp = 1.0 / zDepth;
    let gridP = toVanish * persp * gridScale;

    // Audio wind warp on grid lines
    let wind = sin(gridP.y * 0.5 + time * 3.0 + bass * 4.0) * distortStrength * 0.1 * (1.0 + bass);
    let warpP = gridP + vec2<f32>(wind, 0.0);

    // Shockwave from mouse click
    let clickRipple = 0.0;
    let clickPhase = 0.0;
    if (mouseDown > 0.5) {
      let clickDist = length(p - vanish);
      clickPhase = clickDist * 20.0 - time * 15.0;
      clickRipple = sin(clickPhase) * exp(-clickDist * 3.0) * 0.3;
    }

    let finalP = warpP + vec2<f32>(clickRipple, clickRipple);

    let gridX = abs(fract(finalP.x) - 0.5);
    let gridY = abs(fract(finalP.y) - 0.5);
    let gridLine = min(gridX, gridY);

    let thickness = 0.04 + 0.02 * persp;
    let mouseInfluence = smoothstep(radius, 0.0, length(p - vanish));
    let currentThickness = thickness + mouseInfluence * 0.06;

    let gridMask = 1.0 - smoothstep(currentThickness, currentThickness + 0.04, gridLine);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Thin-film interference on grid lines
    let film = thinFilm(gridLine * 8.0 + time * 0.5 + depth * 3.0, 1.33);
    var iridescent = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.8, 0.0), film.g);
    iridescent = mix(iridescent, vec3<f32>(1.0, 0.0, 1.0), film.b * 0.5);

    let totalGlow = glowIntensity * (0.4 + 0.6 * mouseInfluence + bass * 0.3);
    let latticeColor = mix(baseColor.rgb, iridescent, gridMask * totalGlow);

    // Invert interference colors inside shockwave ring
    if (mouseDown > 0.5 && abs(fract(clickPhase / 6.28318530718) - 0.5) < 0.1) {
      latticeColor = mix(latticeColor, 1.0 - iridescent, 0.5);
    }

    let latticeAlpha = clamp(gridMask * totalGlow * (0.6 + depth * 0.4) + baseColor.a * 0.3, 0.0, 1.0);

    textureStore(writeTexture, coords, vec4<f32>(latticeColor, latticeAlpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(latticeColor, latticeAlpha));
}
