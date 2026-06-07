// ═══════════════════════════════════════════════════════════════════
//  Polka Dot Reveal
//  Category: artistic
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
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

    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevBass = prev.r;
    let prevMouse = prev.gb;
    let prevAlpha = prev.a;

    let bass_smooth = bass_env(prevBass, bass, 0.8, 0.15);

    let smoothMouse = mix(prevMouse, mouse, 0.12);
    let mouseVel = length(mouse - smoothMouse);

    let aspect = resolution.x / resolution.y;
    let mAspect = vec2<f32>(smoothMouse.x * aspect, smoothMouse.y);
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let dist = distance(uvAspect, mAspect);

    let densityMin = mix(10.0, 40.0, scale);
    let densityMax = mix(80.0, 250.0, scale);
    let revealRadius = 0.7 + mouseVel * 3.0;
    let density = mix(densityMax, densityMin, smoothstep(0.0, revealRadius, dist));

    let grid_uv = floor(uv * density) / density;
    let cell_center = grid_uv + (0.5 / density);

    let color = textureSampleLevel(readTexture, u_sampler, cell_center, 0.0);
    let lum = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    let audioBoost = 1.0 + bass_smooth * 0.5 + mids * 0.2;
    let clickBoost = select(1.0, 1.4, mouseDown);
    let radius = lum * 0.5 * audioBoost * clickBoost;

    let pulse = 1.0 + sin(time * (0.5 + speed * 2.0)) * 0.06 * speed;
    let animated_radius = radius * pulse;

    let local_uv = fract(uv * density);
    let dist_to_center = distance(local_uv, vec2<f32>(0.5));

    let aa = mix(0.03, 0.15, detail) * density / 50.0;
    let circle = 1.0 - smoothstep(animated_radius - aa, animated_radius + aa, dist_to_center);

    let trailDecay = mix(0.72, 0.96, intensity);
    let trailAlpha = prevAlpha * trailDecay;
    let dotAlpha = max(mix(0.2, 1.0, lum) * intensity * (1.0 + bass_smooth * 0.2), trailAlpha);

    let satBoost = 1.0 + bass_smooth * 0.3 + treble * 0.1;
    let dotColor = vec4<f32>(color.rgb * satBoost, dotAlpha);

    var final_color = mix(vec4<f32>(0.0, 0.0, 0.0, 0.0), dotColor, circle);

    let interaction = clamp(bass_smooth * 0.5 + mouseVel * 2.0 + treble * 0.1, 0.0, 1.0);
    final_color.a = clamp(final_color.a + interaction * 0.25, 0.0, 1.0);
    final_color = clamp(final_color, vec4<f32>(0.0), vec4<f32>(1.0));

    let state = vec4<f32>(bass_smooth, smoothMouse.x, smoothMouse.y, final_color.a);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), state);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
