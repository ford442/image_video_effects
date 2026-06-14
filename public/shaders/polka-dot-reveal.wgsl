// ═══════════════════════════════════════════════════════════════════
//  Polka Dot Reveal
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            depth-aware, hash-jitter, optimized
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-06-14
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
const LUMA: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, LUMA);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(pixel) / res;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let mouseDown = u.zoom_config.w > 0.5;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let scale = clamp(u.zoom_params.z, 0.01, 1.0);
    let detail = clamp(u.zoom_params.w, 0.01, 1.0);

    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass_smooth = bass_env(prev.r, bass, 0.8, 0.15);
    let smoothMouse = mix(prev.gb, mouse, 0.12);
    let mouseVel = length(mouse - smoothMouse);

    let aspect = res.x / res.y;
    let mAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let dist = distance(uvAspect, mAspect);

    let densityMin = mix(10.0, 40.0, scale);
    let densityMax = mix(80.0, 250.0, scale);
    let revealRadius = 0.7 + mouseVel * 3.0;
    let density = mix(densityMax, densityMin, smoothstep(0.0, revealRadius, dist));

    // Per-cell hash jitter (blue-noise substitute) to break halftone banding
    let jitter = (hash21(uv * 131.0 + vec2<f32>(17.0, 31.0)) - 0.5) / density;
    let grid_uv = floor((uv + jitter) * density) / density;
    let cell_center = grid_uv + (0.5 / density);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let color = textureSampleLevel(readTexture, u_sampler, cell_center, 0.0);
    let lum = luma(color.rgb);

    let audioBoost = 1.0 + bass_smooth * 0.5 + mids * 0.2;
    let clickBoost = select(1.0, 1.4, mouseDown);
    let depthBoost = 1.0 + depth * 0.35;
    let radius = lum * 0.5 * audioBoost * clickBoost * depthBoost;

    let pulse = 1.0 + sin(time * (0.5 + speed * 2.0)) * 0.06 * speed;
    let animated_radius = radius * pulse;

    let local_uv = fract((uv + jitter) * density);
    let dist_to_center = distance(local_uv, vec2<f32>(0.5));

    let aa = mix(0.03, 0.15, detail) * density / 50.0;
    let circle = 1.0 - smoothstep(animated_radius - aa, animated_radius + aa, dist_to_center);

    let trailDecay = mix(0.72, 0.96, intensity);
    let trailAlpha = prev.a * trailDecay;
    let dotAlpha = max(mix(0.2, 1.0, lum) * intensity * (1.0 + bass_smooth * 0.2), trailAlpha);

    let satBoost = 1.0 + bass_smooth * 0.3 + treble * 0.1;
    var final_color = vec4<f32>(color.rgb * satBoost, dotAlpha);
    final_color = mix(vec4<f32>(0.0), final_color, circle);

    let interaction = clamp(bass_smooth * 0.5 + mouseVel * 2.0 + treble * 0.1, 0.0, 1.0);
    final_color.a = clamp(final_color.a + interaction * 0.25, 0.0, 1.0);
    final_color = clamp(final_color, vec4<f32>(0.0), vec4<f32>(1.0));

    let state = vec4<f32>(bass_smooth, smoothMouse.x, smoothMouse.y, final_color.a);

    textureStore(writeTexture, pixel, final_color);
    textureStore(dataTextureA, pixel, state);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
