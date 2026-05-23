// ═══════════════════════════════════════════════════════════════════
//  Quantum Tunnel Interactive
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
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
    let texel = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / max(resolution, vec2<f32>(0.001));
    let aspect = resolution.x / max(resolution.y, 0.001);

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let tunnelStrength = clamp(u.zoom_params.x * (1.0 + bass * 0.2), 0.0, 1.0);
    let aberration     = clamp(u.zoom_params.y * (1.0 + mids * 0.15), 0.0, 1.0);
    let pulseSpeed     = clamp(u.zoom_params.z * (1.0 + treble * 0.1), 0.0, 1.0);
    let spiral         = u.zoom_params.w;

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    var center = mouse;

    // Correct for aspect ratio for distance calculation
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let centerAspect = vec2<f32>(center.x * aspect, center.y);
    let offset = uvAspect - centerAspect;
    let dist = length(offset);
    let angle = atan2(offset.y, offset.x);

    // Dynamic Pulse (audio-reactive)
    let time = u.config.x;
    let audioPulse = 1.0 + bass * 0.5;
    let pulse = sin(dist * 20.0 - time * (pulseSpeed * 10.0 * audioPulse)) * 0.05 * tunnelStrength;

    // Twist
    let twistAngle = angle + (1.0 - smoothstep(0.0, 1.0, dist)) * (spiral * 5.0) * sin(time);

    // Zoom factor
    let zoom = 1.0 - (tunnelStrength * 0.5 * smoothstep(1.0, 0.0, dist));

    // Chromatic Aberration: Sample R, G, B at different scales/twists
    let abbrScale = aberration * 0.05 * dist;

    let rR = dist * (zoom - abbrScale);
    let rG = dist * zoom;
    let rB = dist * (zoom + abbrScale);

    let offR = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rR;
    let offG = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rG;
    let offB = vec2<f32>(cos(twistAngle), sin(twistAngle)) * rB;

    // Convert back to UV space (undo aspect correction)
    let uvR = clamp(vec2<f32>(offR.x / aspect, offR.y) + center, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(vec2<f32>(offG.x / aspect, offG.y) + center, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(vec2<f32>(offB.x / aspect, offB.y) + center, vec2<f32>(0.0), vec2<f32>(1.0));

    let cR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let cG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let cB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Luminance-based alpha
    let luminance = dot(vec3<f32>(cR, cG, cB), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luminance + tunnelStrength * 0.3, 0.0, 1.0);
    var color = vec4<f32>(cR, cG, cB, alpha);

    // Glow at the mouse cursor (audio-reactive)
    let glow = 1.0 - smoothstep(0.0, 0.1, dist);
    let glowColor = vec3<f32>(0.2, 0.4, 1.0) * (1.0 + bass * 2.0);
    color = vec4<f32>(color.rgb + glowColor * glow * tunnelStrength, color.a);

    // Depth read and mandatory writes
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let finalColor = color;

    textureStore(writeTexture, texel, finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
