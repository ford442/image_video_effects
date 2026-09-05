// ═══════════════════════════════════════════════════════════════════
//  Lighthouse Reveal
//  Category: lighting-effects
//  Features: mouse-driven, reveal, beam, audio-sweep, depth-atmosphere
//  Complexity: Medium
//  Updated: 2026-05-31 — Grok (audio-reactive sweep + depth atmosphere)
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

// Lighthouse Reveal
// Param 1: Beam Length (Radius)
// Param 2: Beam Width (Angle)
// Param 3: Edge Softness
// Param 4: Ambient Light

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u2.x), mix(c, d, u2.x), u2.y);
}

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var a = 0.5;
    var s = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
        s = s + noise(p) * a;
        p = p * 2.04 + vec2<f32>(8.7, 3.1);
        a = a * 0.5;
    }
    return s;
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    if (t <= 66.0) { r = 1.0; }
    else { r = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0); }
    if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
    else { g = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0); }
    if (t >= 66.0) { b = 1.0; }
    else if (t <= 19.0) { b = 0.0; }
    else { b = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0); }
    return vec3<f32>(r, g, b);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Correct UV for aspect ratio for distance calculations
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    var mouse = get_mouse();
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let radius = u.zoom_params.x * (1.0 + mids * 0.3);
    let beam_width = u.zoom_params.y * (1.0 + treble * 0.4);
    let softness = u.zoom_params.z;
    let ambient = u.zoom_params.w;
    let time = u.config.x;

    let dist = distance(uv_aspect, mouse_aspect);
    let angle = atan2(uv_aspect.y - mouse_aspect.y, uv_aspect.x - mouse_aspect.x);

    // Grok: Bass pulses the reveal strength (dramatic sweeps)
    let revealPulse = 1.0 + bass * 0.6;

    // Rotation speed with audio reactivity
    let rotation = time * 2.0 * (1.0 + bass * 0.5);

    // Normalize angle difference to -PI to PI
    var angle_diff = angle - rotation;
    let pi = 3.14159265;
    angle_diff = (fract((angle_diff / (2.0 * pi)) + 0.5) - 0.5) * 2.0 * pi;

    // Calculate Beam Mask
    let angle_dist = abs(angle_diff);
    let angle_mask = 1.0 - smoothstep(beam_width * pi * 0.5, (beam_width * pi * 0.5) + softness + 0.01, angle_dist);

    // Radial falloff
    let radial_mask = 1.0 - smoothstep(radius, radius + softness + 0.01, dist);

    let dust = fbm(uv_aspect * 4.5 + vec2<f32>(time * 0.08, -time * 0.03));
    let shaft = pow(angle_mask, 2.2) * radial_mask * (0.55 + dust * 0.75);
    let halo = exp(-dist * 5.5) * (0.45 + bass * 0.45);
    let mist = smoothstep(0.12, 0.92, dust) * pow(radial_mask, 1.6);

    // Combined mask
    let mask = clamp(angle_mask * radial_mask + halo * 0.45, 0.0, 1.0);

    // Apply lighting preserving alpha
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let visibility = mix(ambient * 0.55, 1.0, mask);
    let lampColor = blackbodyRGB(2600.0 + bass * 1800.0 + treble * 900.0);
    let fogColor = mix(vec3<f32>(0.05, 0.07, 0.11), vec3<f32>(0.52, 0.62, 0.78), mist);
    let depthFog = 1.0 - exp(-max(depth, 0.02) * (0.85 + mids * 0.5));
    var hdr = texColor.rgb * visibility;
    hdr = mix(hdr, fogColor, clamp(depthFog * (1.0 - mask) * 0.32, 0.0, 0.55));
    hdr = hdr + lampColor * shaft * (1.35 + bass * 1.1);
    hdr = hdr + lampColor * halo * 0.85;

    let radial = length(uv - vec2<f32>(0.5)) * 1.414;
    hdr = hdr * mix(1.0, 0.62, smoothstep(0.55, 1.0, radial));
    let dither = (ign(vec2<f32>(global_id.xy) + time * 23.0) - 0.5) / 255.0;
    let finalRGB = clamp(aces(hdr * 1.12) + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));
    let luma = dot(hdr, vec3<f32>(0.2126, 0.7152, 0.0722));
    let finalAlpha = clamp(0.12 + pow(max(0.0, luma - 0.45), 2.0) * 2.5 + shaft * 0.28, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB * finalAlpha, finalAlpha));

    // Depth pass-through
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
