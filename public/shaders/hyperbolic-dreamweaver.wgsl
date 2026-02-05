// ═══════════════════════════════════════════════════════════════
// Hyperbolic Dreamweaver - PASS 1 of 1
// Generates infinite non-Euclidean tilings in Poincaré disk model.
// Weaves input image through hyperbolic transformations with psychedelic
// color dispersion, depth-aware curvature, and mouse-centered view.
// Previous: N/A | Next: N/A
// ═══════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=tileCount, y=curvature, z=aberrationStr, w=glowInt
  ripples: array<vec4<f32>, 50>,
};

fn hash(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453);
}

fn rotate(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

fn poincare_distance(p: vec2<f32>) -> f32 {
    return length(p);
}

fn mobius_transform(p: vec2<f32>, center: vec2<f32>, scale: f32, angle: f32) -> vec2<f32> {
    let q = p - center;
    q = rotate(q, angle);
    let d = length(q);
    let hyperbolic_scale = scale / (1.0 + d * d * 0.5);
    return center + q * hyperbolic_scale;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let params = u.zoom_params; // x=tileCount, y=curvature, z=aberrationStr, w=glowInt

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let curvature = mix(0.5, 2.0, depth) * params.y; // Depth-aware curvature
    let tileCount = round(params.x * 6.0) + 3.0; // 3-9 tiles
    let aberrationStr = params.z;
    let glowInt = params.w;

    // Center view on mouse with time animation
    var center = mouse;
    center = mix(center, vec2(0.5), 0.3 * sin(time * 0.5));
    center = 0.5 + (center - 0.5) * (1.0 + 0.5 * sin(time * 0.2));

    // Poincaré disk hyperbolic distance
    let disk_uv = (uv - center) * curvature;
    let disk_dist = poincare_distance(disk_uv);

    // Tile with Möbius transformations
    var final_uv = disk_uv;
    let n_tiles = i32(tileCount);
    for (var i: i32 = 0; i < n_tiles; i = i + 1) {
        let angle = f32(i) * 6.28318 / f32(tileCount) + time * 0.3;
        let scale = 1.0 + 0.5 * sin(f32(i) + time * 2.0);
        final_uv = mobius_transform(final_uv, vec2(0.0), scale, angle);
    }

    // Clamp to disk
    let clamp_dist = 0.95 / (1.0 + disk_dist);
    final_uv = mix(final_uv, disk_uv, 1.0 - clamp_dist);

    // Chromatic aberration in hyperbolic space
    let r_offset = final_uv + vec2(aberrationStr * disk_dist, 0.0);
    let g_offset = final_uv;
    let b_offset = final_uv - vec2(aberrationStr * disk_dist, 0.0);

    let col_r = textureSampleLevel(readTexture, u_sampler, r_offset, 0.0).r;
    let col_g = textureSampleLevel(readTexture, u_sampler, g_offset, 0.0).g;
    let col_b = textureSampleLevel(readTexture, u_sampler, b_offset, 0.0).b;

    var color = vec4(col_r, col_g, col_b, 1.0);

    // Psychedelic glow along symmetry lines
    let symmetry = abs(fract((atan2(final_uv.y, final_uv.x) / 6.28318) * f32(tileCount)) - 0.5) * 2.0;
    let glow = exp(-symmetry * 10.0) * glowInt * (0.5 + 0.5 * sin(time * 5.0 + disk_dist * 10.0));
    color.rgb += glow * vec3(1.0, 0.8, 1.2);

    // Ripple interaction
    let rippleCount = u32(u.config.y);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rippleDist = length(uv - ripple.xy);
        if (rippleDist < 0.1) {
            color.rgb += vec3(0.5 * sin(time - ripple.z) * (1.0 - rippleDist * 10.0));
        }
    }

    // Final tone mapping for psychedelic pop
    color.rgb = pow(color.rgb, vec3(0.8));
    color.rgb *= 1.0 + 0.5 * depth; // Depth pop

    textureStore(writeTexture, global_id.xy, color);

    // Pass depth with hyperbolic modulation for chaining
    let modulated_depth = depth * (1.0 - disk_dist * 0.5);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(modulated_depth, 0.0, 0.0, 0.0));
}
