// --- RAIN LENS WIPE ---
// Simulates raindrops on a lens. The mouse wipes them away, and they slowly return.
// Uses feedback loop for the "wiped" state.

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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn rainDistortion(uv: vec2<f32>, t: f32, scale: f32) -> vec2<f32> {
    let st = uv * scale;
    let i_st = floor(st);
    let f_st = fract(st);

    var m_dist = 1.0;
    var offset = vec2<f32>(0.0);

    // Check 3x3 neighbors to find closest drop center
    for(var y = -1; y <= 1; y++) {
        for(var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var point = hash22(i_st + neighbor);

            // Jitter the drop position over time slightly
            point = 0.5 + 0.3 * sin(t * 0.5 + 6.28 * point);

            let diff = neighbor + point - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                m_dist = dist;
                // Distortion pulls towards the center of the drop (lens effect)
                // Or pushes away? Convex lens inverts.
                // Let's use the vector 'diff' which points to the drop center.
                offset = diff;
            }
        }
    }

    // Drop shape profile
    let dropSize = 0.45;
    let drop = smoothstep(dropSize, dropSize - 0.1, m_dist);
    return offset * drop;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    let rainStrength = u.zoom_params.x;      // Slider 1: Distortion Strength
    let decaySpeed = 0.005 + u.zoom_params.y * 0.05; // Slider 2: Re-fog Speed
    let wipeRadius = 0.05 + u.zoom_params.z * 0.3;  // Slider 3: Wipe Radius
    let rainScale = 5.0 + u.zoom_params.w * 20.0;   // Slider 4: Drop Density

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));

    // Feedback: Read previous "Clean State" from C
    // 1.0 = Clean (Wiped), 0.0 = Rainy
    let prevState = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

    // Decay the clean state back to 0.0 (rainy)
    var newState = max(0.0, prevState - decaySpeed);

    // Apply Wipe (Mouse acts as a squeegee)
    if (mouseDist < wipeRadius) {
         let brush = smoothstep(wipeRadius, wipeRadius * 0.5, mouseDist);
         newState = max(newState, brush);
    }

    // Generate Rain Distortion
    let distortVec = rainDistortion(uv, u.config.x, rainScale);

    // Effective Distortion: modulated by (1.0 - newState)
    // If clean, distortion is 0.
    let finalDistort = distortVec * rainStrength * 0.1 * (1.0 - newState);

    // Sample Color
    let finalUV = uv + finalDistort;
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Add some specular highlights to the drops if they are visible
    // Based on 'finalDistort' magnitude or recalculated drop profile.
    // Quick hack: if distorted, brighten slightly
    let wetness = length(finalDistort) * 20.0; // aprox
    color += vec4<f32>(wetness * 0.1);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Store State for next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newState, 0.0, 0.0, 1.0));

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
