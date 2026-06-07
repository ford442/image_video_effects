// ═══════════════════════════════════════════════════════════════════
//  Kaleido-Scope Prism grokcf1
//  Category: geometric
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Global state update (branchless) ───────────────────────────
    let isStatePixel = global_id.x == 0u && global_id.y == 0u;
    let stateRead = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);

    let mouse_target = u.zoom_config.yz;
    let dt = 0.016;
    let dir = mouse_target - stateRead.gb;
    let dist_to_target = length(dir);
    let ndir = select(vec2<f32>(0.0), dir / max(dist_to_target, 0.0001), dist_to_target > 0.001);
    let prevVel = stateRead.a;
    let force = dist_to_target * 12.0 - prevVel * 3.0;
    let newVel = prevVel + force * dt;
    let newSpring = stateRead.gb + ndir * newVel * dt;
    let attack = select(0.15, 0.8, bass > stateRead.r);
    let newEnv = mix(stateRead.r, bass, attack);

    let env = select(stateRead.r, newEnv, isStatePixel);
    let mouseX = select(stateRead.g, newSpring.x, isStatePixel);
    let mouseY = select(stateRead.b, newSpring.y, isStatePixel);
    let mouse = vec2<f32>(mouseX, mouseY);
    let stateOut = vec4<f32>(newEnv, newSpring, newVel);

    // ── Kaleidoscope core ──────────────────────────────────────────
    let segments_param = u.zoom_params.x;
    let rot_speed = u.zoom_params.y;
    let zoom = u.zoom_params.z;
    let offset_param = u.zoom_params.w;

    let num_segments = 3.0 + floor(segments_param * 12.0);
    let rel_uv = uv - mouse;
    let aspect_uv = vec2<f32>(rel_uv.x * aspect, rel_uv.y);

    let dist = length(aspect_uv);
    var angle = atan2(aspect_uv.y, aspect_uv.x);

    let segment_angle = 6.28318 / num_segments;
    let time = u.config.x * (rot_speed - 0.5) * 2.0;
    angle = angle + time;

    angle = angle - segment_angle * floor(angle / segment_angle);
    angle = select(angle, segment_angle - angle, angle > segment_angle * 0.5);

    let scale = 2.0 - zoom * 1.8;
    let radius = dist * scale + offset_param * 0.5;
    let new_vec = vec2<f32>(cos(angle), sin(angle)) * radius;
    let sample_uv = clamp(vec2<f32>(0.5, 0.5) + vec2<f32>(new_vec.x / aspect, new_vec.y), vec2<f32>(0.0), vec2<f32>(1.0));

    // ── Sample & prism ─────────────────────────────────────────────
    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

    let prism_shift = sin(angle * 6.0 + time) * (0.02 + env * 0.06);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + vec2<f32>(prism_shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv - vec2<f32>(prism_shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec3<f32>(r, color.g, b);

    // ── Reflections ────────────────────────────────────────────────
    let reflect_uv = clamp(vec2<f32>(0.5, 0.5) - vec2<f32>(new_vec.x / aspect, new_vec.y), vec2<f32>(0.0), vec2<f32>(1.0));
    let reflect_color = textureSampleLevel(readTexture, u_sampler, reflect_uv, 0.0).rgb * (0.3 + env * 0.4);
    color += reflect_color;

    // ── Mouse click burst ──────────────────────────────────────────
    let click_pulse = select(1.0, 1.3, u.zoom_config.w > 0.5);
    color *= click_pulse;

    // ── Audio modulation ───────────────────────────────────────────
    color *= (1.0 + bass * 0.1 + mids * 0.05 + treble * 0.05);

    // ── Alpha ──────────────────────────────────────────────────────
    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let effect_intensity = clamp(0.5 + dist * 0.5, 0.0, 1.0);
    let alpha = clamp(0.25 + luminance * 0.7 * effect_intensity, 0.0, 1.0);

    // ── Temporal feedback trails ───────────────────────────────────
    let decay = 0.88;
    let trail_rgb = mix(color, prev.rgb * decay, 0.35);
    let trail_alpha = mix(alpha, prev.a * decay, 0.35);
    let trailColor = vec4<f32>(trail_rgb, trail_alpha);
    let centerColor = vec4<f32>(color, alpha);

    let finalColor = select(trailColor, centerColor, isStatePixel);
    let dataAOut = select(trailColor, stateOut, isStatePixel);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, dataAOut);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
