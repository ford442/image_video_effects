// ═══════════════════════════════════════════════════════════════
//  Lichtenberg Fractal
//  Simulates high-voltage electrical branching (Lichtenberg figures)
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // y=MouseX, z=MouseY
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Parameters
    let growthSpeed = u.zoom_params.x * 0.9 + 0.1; // Probability of growth
    let branching = u.zoom_params.y; // 0 to 1
    let burnIntensity = u.zoom_params.z * 5.0;
    let clearCanvas = u.zoom_params.w; // If > 0.5, clear

    // Read previous state (R=Charge/Burn, G=Age)
    // 0 = Empty, 0.0-0.5 = Charging, 0.5-1.0 = Burnt
    let oldState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);

    var newState = oldState;

    // Mouse Interaction: Start burning
    let dist = distance(uv * vec2<f32>(resolution.x/resolution.y, 1.0), mouse * vec2<f32>(resolution.x/resolution.y, 1.0));
    if (dist < 0.01 && mouse.x >= 0.0) {
        newState.r = 1.0; // Ignite
        newState.g = 0.0; // Age 0
    }

    // Simulation Step
    if (newState.r == 0.0) {
        // Potential to catch fire from neighbors
        // Check 3x3 neighbors
        var maxNeighbor = 0.0;
        let texel = 1.0 / resolution;

        // Random check to save performance and make it jagged
        if (hash(uv + vec2<f32>(time)) < growthSpeed) {
            for (var i = -1; i <= 1; i++) {
                for (var j = -1; j <= 1; j++) {
                    if (i==0 && j==0) { continue; }
                    let nVal = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(f32(i), f32(j)) * texel, 0.0).r;
                    if (nVal > 0.8) { // Only burn if neighbor is fully ignited
                         maxNeighbor = max(maxNeighbor, nVal);
                    }
                }
            }

            if (maxNeighbor > 0.0) {
                // Growth chance
                if (hash(uv * 10.0 + time) < (0.1 + branching * 0.2)) {
                    newState.r = 1.0; // Ignite
                }
            }
        }
    } else {
        // Already burning/burnt
        // Age the burn
        newState.g += 0.01;
        // Fade out active charge to static burn
        if (newState.r > 0.5) {
             newState.r = max(0.5, newState.r - 0.01);
        }
    }

    // Clear canvas
    if (clearCanvas > 0.5) {
        newState = vec4<f32>(0.0);
    }

    // Write state
    textureStore(dataTextureA, global_id.xy, newState);

    // Render Logic
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Electric Blue/White for active burn (r > 0.8)
    // Charred Black for old burn (r <= 0.5)

    var finalColor = baseColor;

    if (newState.r > 0.0) {
        if (newState.r > 0.8) {
            // Active electric arc
            let electricity = vec3<f32>(0.5, 0.8, 1.0) * burnIntensity;
            finalColor += electricity;
        } else {
            // Charred path
            let charColor = vec3<f32>(0.1, 0.05, 0.0);
            finalColor = mix(finalColor, charColor, 0.8);
        }
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
