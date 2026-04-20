// ═══════════════════════════════════════════════════════════════════
//  frost-reveal-crystal
//  Category: advanced-hybrid
//  Features: frost-reveal, crystal-growth, temporal, mouse-driven
//  Complexity: Very High
//  Chunks From: frost-reveal.wgsl, alpha-crystal-growth-phase.wgsl
//  Created: 2026-04-18
//  By: Agent CB-21 — Distortion & Material Enhancer
// ═══════════════════════════════════════════════════════════════════
//  A frost layer that melts to reveal growing crystal dendrites
//  beneath. The crystal phase field evolves in real-time, creating
//  anisotropic branching patterns. Where frost is thick, crystals
//  grow slowly; where melted, the crystal structure is fully visible.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)),
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)),
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pos = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let coord = vec2<i32>(i32(global_id.x), i32(global_id.y));
    let ps = 1.0 / resolution;

    // Parameters
    let growth_speed = u.zoom_params.x * 0.05;
    let melt_radius = u.zoom_params.y * 0.3 + 0.01;
    let max_opacity = u.zoom_params.z;
    let anisotropy = mix(0.0, 0.5, u.zoom_params.w);

    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Read previous states
    let prev_mask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    let prev_crystal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    // Frost mask update
    var mask = prev_mask;
    let melt = smoothstep(melt_radius, melt_radius * 0.5, dist);
    mask = mix(mask, 0.0, melt);
    mask += growth_speed * (1.0 - mask * 0.5); // Slower growth where mask is thick
    mask = clamp(mask, 0.0, 1.0);

    // Crystal phase field (simplified stateless for hybrid)
    var phase = prev_crystal.g;
    var orientation = prev_crystal.b;
    var impurity = prev_crystal.a;

    if (time < 0.1) {
        phase = 0.0;
        orientation = 0.0;
        impurity = hash12(uv * 100.0) * 0.1;
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.02) {
            phase = 1.0;
            orientation = atan2(uv.y - 0.5, uv.x - 0.5);
        }
    }

    phase = clamp(phase, 0.0, 1.0);
    impurity = clamp(impurity, 0.0, 1.0);

    // Anisotropic growth simulation
    let left = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, non_filtering_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapPhase = left.g + right.g + down.g + up.g - 4.0 * phase;
    let gradPhase = vec2<f32>(right.g - left.g, up.g - down.g) * 0.5;
    let angle = orientation;
    let dir = vec2<f32>(cos(angle), sin(angle));
    let alignment = abs(dot(normalize(gradPhase + vec2<f32>(0.0001)), dir));
    let anisoFactor = 1.0 + anisotropy * (alignment - 0.5) * 2.0;

    let supercooling = 0.5;
    let m = supercooling * (1.0 - 2.0 * impurity);
    let phaseReaction = phase * (1.0 - phase) * (phase - 0.5 + m * 0.5);
    let growthRate = mix(0.001, 0.01, u.zoom_params.x);
    phase += phaseReaction * growthRate * anisoFactor + lapPhase * 0.1 * growthRate;
    phase = clamp(phase, 0.0, 1.0);

    // Orientation diffusion
    let lapOrient = left.b + right.b + down.b + up.b - 4.0 * orientation;
    orientation += lapOrient * 0.01 * phase;
    if (phase > 0.1 && phase < 0.9) {
        orientation = mix(orientation, atan2(gradPhase.y, gradPhase.x), 0.05);
    }

    // Mouse seeds crystals
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mouse);
    let mouseInfluence = smoothstep(0.04, 0.0, mouseDist) * mouseDown;
    phase = mix(phase, 1.0, mouseInfluence);
    if (mouseInfluence > 0.01) {
        orientation = atan2(uv.y - mouse.y, uv.x - mouse.x);
    }

    // Store states
    textureStore(dataTextureA, coord, vec4<f32>(mask, phase, orientation, impurity));

    // Generate frost visuals
    let frost_pattern = fbm(uv * 10.0);
    let frost_detail = fbm(uv * 20.0);
    let combined_frost = smoothstep(0.3, 0.7, frost_pattern * 0.6 + frost_detail * 0.4);
    let offset = (vec2<f32>(frost_pattern, frost_detail) - 0.5) * 0.05 * mask;
    let distorted_uv = uv + offset;

    // Crystal color based on orientation
    let orientNorm = fract(orientation / 6.283185307);
    let h6 = orientNorm * 6.0;
    let c = 0.8;
    let x = c * (1.0 - abs(h6 - floor(h6 / 2.0) * 2.0 - 1.0));
    var crystalColor: vec3<f32>;
    if (h6 < 1.0) { crystalColor = vec3(c, x, 0.3); }
    else if (h6 < 2.0) { crystalColor = vec3(x, c, 0.3); }
    else if (h6 < 3.0) { crystalColor = vec3(0.3, c, x); }
    else if (h6 < 4.0) { crystalColor = vec3(0.3, x, c); }
    else if (h6 < 5.0) { crystalColor = vec3(x, 0.3, c); }
    else { crystalColor = vec3(c, 0.3, x); }

    let interfaceMask = smoothstep(0.3, 0.5, phase) * smoothstep(0.7, 0.5, phase);
    let interfaceColor = vec3<f32>(0.9, 0.95, 1.0);
    let liquidColor = vec3<f32>(0.05, 0.08, 0.15);
    var displayColor = mix(liquidColor, crystalColor, smoothstep(0.4, 0.6, phase));
    displayColor = mix(displayColor, interfaceColor, interfaceMask * 0.5);
    displayColor = mix(displayColor, vec3<f32>(0.8, 0.6, 0.4), impurity * 0.3);

    // Sample original image
    let clear_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let frost_color_sample = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0);
    let frost_tint = vec4<f32>(0.9, 0.95, 1.0, 1.0);
    let frosted_look = mix(frost_color_sample, frost_tint, 0.4 * mask * max_opacity);

    // Mix: frost -> crystal -> clear image
    let visibility = mask * combined_frost * max_opacity;
    let crystalVisibility = smoothstep(0.4, 0.6, phase) * (1.0 - mask);
    var final_color = mix(clear_color, frosted_look, visibility);
    final_color = mix(final_color, vec4<f32>(displayColor, 1.0), crystalVisibility * 0.8);

    textureStore(writeTexture, coord, final_color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
