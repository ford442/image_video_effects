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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi_edge(uv: vec2<f32>, scale: f32) -> vec3<f32> {
    let p = uv * scale;
    let i = floor(p);
    let f = fract(p);

    var m_dist = 10.0;
    var m_id = vec2<f32>(0.0);
    var m_diff = vec2<f32>(0.0);

    // First pass: Find closest cell center
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i + neighbor);
            let diff = neighbor + point - f;
            let dist = length(diff);
            if (dist < m_dist) {
                m_dist = dist;
                m_id = i + neighbor;
                m_diff = diff;
            }
        }
    }

    // Second pass: Find distance to closest edge (border between cells)
    var m_border = 10.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i + neighbor);
            let diff = neighbor + point - f;

            // Skip the closest center itself
            if (dot(diff - m_diff, diff - m_diff) > 0.00001) {
                let r = diff - m_diff;
                // Distance to the perpendicular bisector
                let d = dot(0.5 * (diff + m_diff), normalize(r));
                m_border = min(m_border, d);
            }
        }
    }

    return vec3<f32>(m_dist, m_border, m_id.x + m_id.y * 57.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) {
        return;
    }

    let pixel_pos = vec2<f32>(gid.xy);
    let uv = pixel_pos / resolution;

    // Correct Aspect Ratio for Voronoi
    let aspect = resolution.x / resolution.y;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    // Voronoi Scale
    let scale = 6.0;

    let v = voronoi_edge(uv_aspect, scale);
    let dist_to_center = v.x;
    let dist_to_edge = v.y; // 0.0 at edge, increasing towards center
    let cell_id = v.z;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let mouse_dist = distance(uv_aspect, mouse_aspect);

    // "Heal" Logic: cracks disappear near mouse
    // Radius of healing
    let heal_radius = 0.3;
    let heal_factor = smoothstep(heal_radius, 0.0, mouse_dist);

    // Crack Thickness
    let base_thickness = 0.03;
    let thickness = base_thickness * (1.0 - heal_factor);

    // Shard Offset (Displacement)
    // Random offset per cell
    let offset_rng = hash22(vec2<f32>(cell_id, cell_id));
    let shard_offset = (offset_rng - 0.5) * 0.05 * (1.0 - heal_factor);

    var final_color = vec3<f32>(0.0);

    if (dist_to_edge < thickness) {
        // Gold Crack
        // Simulate a rounded metallic surface for the crack
        // Normalize dist_to_edge to -1..1 range across the crack width?
        // dist_to_edge goes from 0 (at border) to +inf.
        // We are only drawing where dist_to_edge < thickness.
        // So 0 is center of crack? No, dist_to_edge is 0 at the Voronoi boundary.
        // So the crack is centered on the boundary.
        // The "profile" of the crack is 0 to thickness.

        let t = dist_to_edge / thickness; // 0 to 1

        // Let's make a simple normal based on this.
        // It's a bevel.
        // Fake normal: Pointing up + some directional bias
        let normal = normalize(vec3<f32>(t * 2.0 - 1.0, 0.0, 1.0));

        // Lighting
        let time = u.config.x;
        let light_dir = normalize(vec3<f32>(sin(time), cos(time), 1.0));
        let view_dir = vec3<f32>(0.0, 0.0, 1.0);

        // Reflection
        let ref = reflect(-light_dir, normal);
        let spec = pow(max(dot(ref, view_dir), 0.0), 40.0);

        let gold = vec3<f32>(1.0, 0.84, 0.0);
        let ambient = vec3<f32>(0.2, 0.15, 0.0);

        final_color = ambient + gold * spec * 2.0;

        // Add noise to gold
        let noise = hash22(uv * 50.0).x;
        final_color *= (0.8 + 0.2 * noise);

    } else {
        // Image
        // Displace the sampling UV based on the shard offset
        var sample_uv = uv + shard_offset;

        // Clamp
        sample_uv = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));

        final_color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;

        // Add slight shadow at edge of shard
        let shadow = smoothstep(thickness, thickness + 0.05, dist_to_edge);
        final_color *= (0.5 + 0.5 * shadow);
    }

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(final_color, 1.0));
}
