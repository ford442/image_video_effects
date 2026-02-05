// --- PAGE CURL INTERACTIVE ---
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Mouse sets the curl position
    let mouse = u.zoom_config.yz;
    let shadowStrength = u.zoom_params.y;

    // Curl Calculation
    // We assume a vertical curl moving from right to left, controlled by Mouse X.
    // Mouse Y controls the curl radius.

    let rollX = mouse.x;
    let radius = max(0.05, mouse.y * 0.3);

    var col = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    if (uv.x < rollX) {
        // Flat page area
        col = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

        // Shadow cast by the curl
        let distToRoll = rollX - uv.x;
        if (distToRoll < radius) {
            let shadow = smoothstep(radius, 0.0, distToRoll); // 0 at radius, 1 at roll
            col = col * (1.0 - shadow * 0.4 * shadowStrength);
        }
    } else {
        // Curled area
        let dx = uv.x - rollX;
        if (dx < radius) {
            // Backside visible (Cylindrical projection)
            // x_screen = r * sin(theta) -> theta = asin(x_screen/r)
            // arc_len = r * theta
            let theta = asin(clamp(dx/radius, -1.0, 1.0));
            let arcLen = radius * theta;

            let sourceUvX = rollX + arcLen;

            if (sourceUvX <= 1.0) {
                let backColor = textureSampleLevel(readTexture, u_sampler, vec2<f32>(sourceUvX, uv.y), 0.0);
                col = backColor * 0.6; // Darker backside

                // Highlight on the curve
                let normalZ = cos(theta);
                col += vec4<f32>(pow(normalZ, 4.0) * 0.3);
            } else {
                col = vec4<f32>(0.1, 0.1, 0.1, 1.0); // Off page (Background)
            }
        } else {
            col = vec4<f32>(0.05); // Background beyond the curl
        }
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), col);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
