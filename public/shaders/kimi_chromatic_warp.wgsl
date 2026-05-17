// ═══════════════════════════════════════════════════════════════════
//  Kimi Chromatic Warp
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
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

// Kimi Chromatic Warp - RGB channel separation based on mouse distance
// Creates prismatic distortion effects that intensify near the cursor

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let mouse    = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / max(resolution.y, 0.001);
    var p      = uv;
    p.x       *= aspect;

    var mousePos = mouse;
    mousePos.x  *= aspect;

    let delta = p - mousePos;
    let dist  = length(delta);
    let dir   = normalize(delta + vec2<f32>(0.0001));

    // Parameters — bass widens warp radius, mids boost chromatic spread
    let warpRadius      = u.zoom_params.x * 0.8 + 0.05;
    let warpStrength    = u.zoom_params.y * 0.1 + 0.01;
    let chromaticSpread = u.zoom_params.z * 0.05 * (1.0 + mids * 0.4);
    let rotationSpeed   = u.zoom_params.w * 5.0;

    let falloff = smoothstep(warpRadius * (1.0 + bass * 0.15), 0.0, dist);

    let angle  = dist * 10.0 - time * rotationSpeed + mouseDown * 2.0;
    let rotDir = vec2<f32>(
        dir.x * cos(angle) - dir.y * sin(angle),
        dir.x * sin(angle) + dir.y * cos(angle)
    );

    let rOffset = rotDir * (warpStrength + chromaticSpread) * falloff;
    let gOffset = rotDir * warpStrength * falloff;
    let bOffset = rotDir * (warpStrength - chromaticSpread) * falloff * 0.5;

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv - rOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv - gOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - bOffset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let origAlpha = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;

    var color = vec3<f32>(r, g, b);

    // Prismatic ring glow
    let ringWidth = 0.02;
    let ringDist  = abs(dist - warpRadius * 0.7);
    let ring      = smoothstep(ringWidth, 0.0, ringDist) * falloff;
    let hue       = atan2(delta.y, delta.x) / 6.28318 + 0.5;
    let rainbow   = vec3<f32>(
        sin(hue * 6.28318) * 0.5 + 0.5,
        sin(hue * 6.28318 + 2.094) * 0.5 + 0.5,
        sin(hue * 6.28318 + 4.188) * 0.5 + 0.5
    );
    color = mix(color, rainbow, ring * 0.3);

    // Vignette within warp
    let innerVignette = smoothstep(warpRadius * 0.3, warpRadius * 0.8, dist);
    color *= 0.7 + 0.3 * innerVignette;

    // Bass burst on click + treble sparkle
    let burst = mouseDown * exp(-dist * 3.0) * sin(dist * 30.0 - time * 15.0);
    color += vec3<f32>(burst * 0.2 + treble * ring * 0.1);

    // Film grain
    let grain = hash(uv + vec2<f32>(time)) * 0.04 - 0.02;
    color += grain;

    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    // Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Meaningful alpha: warp zone + ring glow + audio energy + original alpha
    let alpha = clamp(falloff * 0.5 + ring * 0.4 + bass * 0.1 + origAlpha * 0.05, 0.0, 1.0);
    let fc = vec4<f32>(color, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
