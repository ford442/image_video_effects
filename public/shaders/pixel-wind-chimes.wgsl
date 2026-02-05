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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,  // x=StripCount, y=SwayAmount, z=WindSpeed, w=GapSize
  ripples: array<vec4<f32>, 50>,
};

fn rotate(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Parameters
    let strip_count = mix(10.0, 80.0, u.zoom_params.x);
    let sway_amp = u.zoom_params.y * 1.5;
    let wind_speed = mix(0.5, 5.0, u.zoom_params.z);
    let gap_size = u.zoom_params.w * 0.5; // 0.0 to 0.5 relative to width

    let strip_width = 1.0 / strip_count;
    let base_idx = floor(uv.x * strip_count);

    var final_color = vec4<f32>(0.05, 0.05, 0.05, 1.0); // Dark background
    var found_hit = false;
    var closest_z = 1000.0; // Depth sorting if needed (here simplified)

    // Check current strip and neighbors for overlap
    // Using loop from -2 to 2 to catch wider swings
    for (var i = -2; i <= 2; i++) {
        let idx = base_idx + f32(i);

        // Check bounds
        if (idx < 0.0 || idx >= strip_count) {
            continue;
        }

        let center_x = (idx + 0.5) * strip_width;

        // --- Calculate Angle for this strip ---
        // Mouse Interaction
        let mouse = u.zoom_config.yz;
        let dist_x = center_x - mouse.x;

        // Repelling force from mouse
        // Using a Gaussian-like push
        let push = exp(-pow(dist_x * 5.0, 2.0));
        let dir = sign(dist_x + 0.001); // Avoid 0
        let mouse_angle = dir * push * sway_amp;

        // Constant wind/ambient sway
        // Phase shift based on index
        let ambient_angle = sin(time * wind_speed + idx * 0.5) * 0.1 * sway_amp;

        let total_angle = ambient_angle + mouse_angle;

        // --- Intersection Test ---
        // We are at pixel `uv`.
        // Transform `uv` into the strip's local coordinate space rotated by `total_angle`.

        // Pivot is top center: (center_x, 0.0)
        let rel_pos = uv - vec2<f32>(center_x, 0.0);

        // Rotate inversely by angle to find position in "un-rotated" strip space
        let local_pos = rotate(rel_pos, -total_angle);

        // Check if `local_pos` is within the strip's bounds
        // Strip extends from x = -width/2 to width/2 (minus gap)
        // And y = 0 to 1 (approx, strips can be longer?) Let's assume infinite length or up to screen bottom.

        let half_w = (strip_width * 0.5) * (1.0 - gap_size);

        if (abs(local_pos.x) < half_w && local_pos.y >= 0.0 && local_pos.y <= 1.0) {
            // Hit!
            // Map back to texture coordinates
            // Texture for this strip is simply the strip of the image at that index.
            // Source X is: center_x + local_pos.x
            // Source Y is: local_pos.y (since pivot is at 0)

            let src_uv = vec2<f32>(center_x + local_pos.x, local_pos.y);

            // Sample
            let col = textureSampleLevel(readTexture, u_sampler, src_uv, 0.0);

            // Lighting / Shading based on angle
            // Simulate light coming from top-front
            // Angle tilts strip away/towards.
            // Simple cosine falloff
            let shade = cos(total_angle * 2.0) * 0.8 + 0.2;

            // Overwrite final color
            // Since we loop -2 to 2, later indices might be "on top"?
            // We need Z-sorting.
            // Z-depth of this pixel on the rotated plane:
            // rotated_pos_z = rel_pos.x * sin(angle) ??
            // Actually, simplified: loop order doesn't guarantee Z.
            // But usually strips don't overlap much unless angle is huge.
            // Let's just take the hit if we haven't found one, or blend?
            // "Painters algorithm" is hard without sorting.
            // Let's assume nearest neighbor (i=0) is closest? Not necessarily.
            // Let's compute Z.
            // Rotated Z (into screen) = x_local * sin(angle) + y_local * (0)?
            // Rotation is around Z axis (2D plane)?
            // Wait, "Swinging" means rotation around X axis (swinging towards/away) or Z axis (swinging left/right like pendulum)?
            // Wind chimes usually swing in 3D.
            // My `rotate` function was 2D rotation (Z-axis rotation).
            // So the strip swings Left/Right.
            // In this case, Z is constant (0). They are all on the same plane.
            // If they overlap, it's just 2D overlap.
            // Priority: Which one is "in front"?
            // Let's say indices are layered? Or just blend?
            // Let's just take the first hit we find, but prioritize the one with smallest `abs(i)` (closest to base index).
            // So we should check i=0 first, then -1, 1...

            // Actually, if we just overwrite, the last one drawn wins.
            // If we want consistent layering, we can use idx.

            final_color = col * shade;
            found_hit = true;

            // If we found a hit, can we break?
        }
    }

    textureStore(writeTexture, global_id.xy, final_color);

    // Depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(0.5, 0.0, 0.0, 0.0));
}
