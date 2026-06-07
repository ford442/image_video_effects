// ═══════════════════════════════════════════════════════════════════
//  Shader: Frost Reveal
//  Category: image
//  Features: frost-growth, dendritic-crystals, mouse-melt, depth-aware,
//            upgraded-rgba, audio-reactive
//  Complexity: Medium
//  Chunks From: noise.wgsl
//  Created: 2026-05-10
//  Upgraded: 2026-05-31
//  By: Claude Opus 4.8 (visual-idea pass 2026-05-31)
//  Unique idea: dendritic ice crystals with hexagonal 6-fold symmetry that branch
//  from nucleation points and grow inward from cold screen edges (real window frost).
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Mask buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous mask
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GrowthSpeed, y=MeltRadius, z=FrostOpacity, w=Distortion
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash3 (from noise.wgsl) ═══
fn hash3(p: vec2f) -> vec3f {
  let q = vec3f(dot(p, vec2f(127.1, 311.7)),
                dot(p, vec2f(269.5, 183.3)),
                dot(p, vec2f(419.2, 371.9)));
  return fract(sin(q) * 43758.5453);
}
// ════════════════════════════════════════

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(mix(hash3(i + vec2<f32>(0.0, 0.0)).x,
                   hash3(i + vec2<f32>(1.0, 0.0)).x, u.x),
               mix(hash3(i + vec2<f32>(0.0, 1.0)).x,
                   hash3(i + vec2<f32>(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    let shift = vec2<f32>(100.0);
    // Rotate to reduce axial bias
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pos = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pos);
        pos = rot * pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ═══ UNIQUE VISUAL IDEA: dendritic ice crystal with hexagonal symmetry ═══
// Ice forms 6-fold-symmetric ferns. We tile space into nucleation cells, fold the
// angle from each cell's seed into 60° wedges, and grow feathery needle branches
// (sharp sine ridges) outward — the characteristic window-frost dendrite.
const TAU: f32 = 6.28318530718;
fn iceCrystal(p: vec2<f32>, t: f32) -> f32 {
    let cellScale = 6.0;
    let g = p * cellScale;
    let cell = floor(g);
    let seed = hash3(cell).x;
    // Nucleus jitter within the cell.
    let nucleus = cell + 0.5 + vec2<f32>(hash3(cell + 3.1).x, hash3(cell + 7.7).x) * 0.6 - 0.3;
    let d = g - nucleus;
    let radius = length(d);
    var ang = atan2(d.y, d.x) + seed * TAU;
    // Fold into 6-fold symmetry (hexagonal ice).
    ang = abs(fract(ang / (TAU / 6.0)) - 0.5);
    // Primary spine + secondary feathered branches along the radius.
    let spine_t = 1.0 - smoothstep(0.0, 0.16, ang);
    let spine = spine_t * spine_t * spine_t;
    let branch_base = max(sin(radius * 26.0 - t * 0.4), 0.0);
    let branch_b2 = branch_base * branch_base;
    let branch_b4 = branch_b2 * branch_b2;
    let branches = branch_b4 * branch_b4 * (1.0 - smoothstep(0.0, 0.34, ang));
    // Crystals fade out past the cell — a finite fern, denser near the nucleus.
    let falloff = exp(-radius * 1.7);
    return saturate((spine * 0.7 + branches * 0.6) * falloff);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Audio reactivity — read once at shader start
    let audio = plasmaBuffer[0].xyz;
    let bass = saturate(audio.x);
    let mids = saturate(audio.y);
    let treble = saturate(audio.z);

    // Parameters — subtle audio modulation (< 15% influence)
    let growth_speed = u.zoom_params.x * 0.05 * (1.0 + (bass - 0.5) * 0.12);
    let melt_radius = u.zoom_params.y * 0.3 + 0.01;
    let max_opacity = u.zoom_params.z;
    let distortion_amt = u.zoom_params.w * 0.05 * (1.0 + (treble - 0.5) * 0.15);

    // Mouse Interaction
    var mouse = u.zoom_config.yz;
    // Aspect ratio correction for distance
    let aspect = resolution.x / resolution.y;
    let dist_vec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dist_vec);

    // Read previous mask state (channel R)
    let prev_mask = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    var mask = prev_mask;

    // Melt logic: if mouse is close, reduce mask value
    // Soft brush
    let melt = smoothstep(melt_radius, melt_radius * 0.5, dist);
    mask = mix(mask, 0.0, melt);

    // Growth logic: slowly increase mask value back to 1.0
    mask += growth_speed;
    mask = saturate(mask);

    // Store new mask — proper alpha carries mask value
    textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, 0.0, 0.0, mask));

    // Generate Frost Visuals
    let frost_pattern = fbm(uv * 10.0 + vec2<f32>(0.0, 0.0)); // Static pattern
    let frost_detail = fbm(uv * 20.0);

    // Dendritic crystal ferns layered over the soft FBM haze base.
    // Treble adds subtle sparkle to crystal intensity.
    let crystal = iceCrystal(uv * vec2<f32>(aspect, 1.0), time) * (1.0 + treble * 0.08);
    // Cold edges nucleate first: frost creeps inward from the screen border.
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeFrost = smoothstep(0.45, 0.0, edgeDist);

    let haze = smoothstep(0.3, 0.7, frost_pattern * 0.6 + frost_detail * 0.4);
    // Crystals are the star; haze + edge nucleation fill the rest.
    let combined_frost = saturate(crystal * 0.9 + haze * 0.4 + edgeFrost * 0.35);

    // Distortion
    let offset = (vec2<f32>(frost_pattern, frost_detail) - 0.5) * distortion_amt * mask;
    let distorted_uv = uv + offset;

    let clear_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let frost_color_sample = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0);

    // Frost is usually whiter/brighter + blurred (simulated by noise offset)
    // Alpha driven by max_opacity rather than hardcoded 1.0
    let frost_tint = vec4<f32>(0.9, 0.95, 1.0, max_opacity);
    let frosted_look = mix(frost_color_sample, frost_tint, 0.4 * mask * max_opacity);

    // Final mix based on mask and frost pattern
    // If mask is 0, show clear. If mask is 1, show frost where pattern exists.
    let visibility = mask * combined_frost * max_opacity;

    // Proper alpha: preserve source alpha, modulate by frost visibility
    let final_alpha = mix(clear_color.a, max_opacity * 0.85, visibility);
    let final_color = vec4<f32>(mix(clear_color.rgb, frosted_look.rgb, visibility), saturate(final_alpha));

    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
